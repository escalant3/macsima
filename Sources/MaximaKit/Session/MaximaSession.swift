// SPDX-License-Identifier: GPL-2.0-or-later
//
// The queue and prompt handling follow wxMaxima's evaluation logic
// (src/Maxima.cpp, src/MaximaEvaluator.cpp, src/MaximaProtocol.h);
// wxMaxima is Copyright (C) Andrej Vodopivec, Gunter Koenigsmann and the
// wxMaxima developers, GPL-2.0-or-later.

import Darwin
import Foundation
import Security

/// One Maxima process driven through the glue Lisp.
///
/// Cells are queued and run one statement at a time: a statement goes out
/// only after the main prompt that ends the previous one. Each cell gets an
/// `AsyncStream<CellEvent>` that ends with `.finished`. Everything else
/// (state changes, session-wide tags, late async output) goes to `events`.
public actor MaximaSession {
    public typealias TransportFactory = @Sendable (MaximaConfiguration) throws(MaximaError) -> any MaximaTransport

    public nonisolated let events: AsyncStream<SessionEvent>
    private nonisolated let eventSink: AsyncStream<SessionEvent>.Continuation
    public private(set) var configuration: MaximaConfiguration
    private let makeTransport: TransportFactory
    private let makeToken: @Sendable () -> String

    public private(set) var state: SessionState = .dead
    /// Whether the interrupt channel authenticated for the current process.
    public private(set) var interruptChannelReady = false
    /// What the glue reported in `*wx-interrupt-channel-available*` (nil: not yet).
    private var interruptChannelPromised: Bool?
    /// The current Maxima process group, for leak checks.
    public var processGroup: pid_t? { transport?.processGroup }
    /// Every process group this session started, for leak checks.
    public private(set) var processGroups: [pid_t] = []
    /// The current private temp folder (`maxima_tempdir`).
    public var tempDirectory: String? { transport?.tempDirectory }

    private var transport: (any MaximaTransport)?
    private var generation = 0
    private var reader: Task<Void, Never>?
    private var scanner = TagScanner()
    private var token = ""
    private var authWaiter: OneShot<Result<Void, MaximaError>>?
    private var lispMode = false
    /// The label of the last main prompt (the next statement's input label).
    private var lastLabel = 1
    private var lastCellID: String?

    private final class CellJob {
        let id: String
        let statements: [Statement]
        let sink: AsyncStream<CellEvent>.Continuation
        var next = 0
        /// The first error, when `abortCellOnError` is off and the cell went on.
        var failure: ErrorKind?
        init(id: String, statements: [Statement], sink: AsyncStream<CellEvent>.Continuation) {
            self.id = id
            self.statements = statements
            self.sink = sink
        }
    }
    private var queue: [CellJob] = []
    private var current: CellJob?
    /// Plain-text lines of the running statement, for error detection.
    private var statementText: [String] = []

    public init(configuration: MaximaConfiguration = MaximaConfiguration()) {
        self.init(configuration: configuration,
                  transport: { config throws(MaximaError) in try ProcessTransport(configuration: config) },
                  token: MaximaSession.randomToken)
    }

    /// For tests: a custom transport and token source.
    public init(configuration: MaximaConfiguration, transport: @escaping TransportFactory,
                token: @escaping @Sendable () -> String) {
        self.configuration = configuration
        makeTransport = transport
        makeToken = token
        (events, eventSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// 64 random bytes, base64: the `MAXIMA_AUTH_CODE` token.
    public static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return (0..<64).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        }
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Lifecycle

    /// Starts Maxima, loads the glue and returns when the session is idle.
    public func start() async throws(MaximaError) {
        guard state == .dead else { throw .busy(String(localized: "Maxima is already running.")) }
        let glue: String
        if let source = configuration.glueSource { glue = source } else { glue = try GlueLisp.bundledSource() }
        let transport = try makeTransport(configuration)
        generation += 1
        let gen = generation
        self.transport = transport
        scanner = TagScanner()
        lispMode = false
        lastLabel = 1
        lastCellID = nil
        interruptChannelReady = false
        interruptChannelPromised = nil
        token = makeToken()
        setState(.starting)
        reader = Task { [weak self] in
            for await event in transport.events {
                await self?.handle(event, generation: gen)
            }
            await self?.transportEnded(generation: gen)
        }

        do {
            try await transport.launch(token: token)
        } catch {
            await abandon(transport, reason: error.description)
            throw error
        }
        if let group = transport.processGroup { processGroups.append(group) }
        guard gen == generation, state == .starting else { throw .notRunning }

        let waiter = OneShot<Result<Void, MaximaError>>()
        authWaiter = waiter
        setState(.authenticating)
        transport.send(GlueLisp.command(from: glue))
        let timeout = Task { [configuration] in
            try await Task.sleep(for: configuration.authenticationTimeout)
            waiter.resolve(.failure(.authenticationFailed("no token after \(configuration.authenticationTimeout)")))
        }
        let result = await waiter.wait()
        timeout.cancel()
        authWaiter = nil
        if case .failure(let error) = result {
            if gen == generation { await abandon(transport, reason: error.description) }
            throw error
        }

        // The channel connects just after the setup lines. When the glue says
        // one is coming, give it a moment so the first interrupt can use it.
        let deadline = ContinuousClock.now + .seconds(3)
        while gen == generation, !interruptChannelReady, interruptChannelPromised != false,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The `.died` and `.sessionDied` reason after `restart`.
    public static let restartReason = String(localized: "Maxima was restarted", comment: "Why a session ended")

    /// Kills Maxima and starts a new one, with `configuration` when given.
    /// Open cells end with `.sessionDied`.
    public func restart(configuration: MaximaConfiguration? = nil) async throws(MaximaError) {
        await kill(reason: Self.restartReason)
        if let configuration { self.configuration = configuration }
        try await start()
    }

    /// Kills Maxima. Open cells end with `.sessionDied`.
    public func kill(reason: String = String(localized: "Maxima was stopped", comment: "Why a session ended")) async {
        guard let transport else { return }
        await abandon(transport, reason: reason)
    }

    /// Kills Maxima and ends `events`. The session cannot be used afterwards.
    public func shutdown() async {
        await kill(reason: String(localized: "Maxima was shut down", comment: "Why a session ended"))
        eventSink.finish()
    }

    /// Detaches the transport, fails everything waiting on it, then kills it.
    private func abandon(_ transport: any MaximaTransport, reason: String) async {
        guard self.transport === transport else { return }
        generation += 1
        self.transport = nil
        reader?.cancel()
        reader = nil
        authWaiter?.resolve(.failure(.authenticationFailed(reason)))
        failAllCells(reason)
        if state != .dead {
            setState(.dead)
            eventSink.yield(.died(reason))
        }
        await transport.terminate()
    }

    private func transportEnded(generation gen: Int) async {
        guard gen == generation, let transport else { return }
        await abandon(transport, reason: String(localized: "Maxima exited"))
    }

    // MARK: - Evaluation

    /// Queues a cell. Throws if its brackets are unbalanced or Maxima is not running.
    public func evaluate(cellID: String, text: String) throws(MaximaError) -> AsyncStream<CellEvent> {
        guard transport != nil, ![.dead, .starting, .authenticating, .configuring].contains(state) else {
            throw .notRunning
        }
        let statements: [Statement]
        if lispMode {
            let trimmed = text.trimmingWhitespace
            statements = trimmed.isEmpty ? [] : [Statement(text: trimmed, terminator: .line)]
        } else {
            do { statements = try StatementSplitter.split(text) } catch { throw .split(error) }
        }
        let (stream, sink) = AsyncStream.makeStream(of: CellEvent.self, bufferingPolicy: .unbounded)
        guard !statements.isEmpty else {
            sink.yield(.finished(.completed))
            sink.finish()
            return stream
        }
        queue.append(CellJob(id: cellID, statements: statements, sink: sink))
        if current == nil { runNext() }
        return stream
    }

    /// Replies to a question or sends a debugger command. Adds the `;` an
    /// answer or an expression needs; break commands (`:bt`, `:next`) take none.
    public func answer(_ text: String) throws(MaximaError) {
        guard let transport, state == .question || state == .debugger else { throw .noQuestion }
        var line = text.trimmingWhitespace
        if !(state == .debugger && line.hasPrefix(":")) && !line.hasSuffix(";") && !line.hasSuffix("$") { line += ";" }
        setState(.busy)
        transport.send(line + "\n")
    }

    /// Interrupts the running statement and drops the queued cells.
    @discardableResult
    public func interrupt(via method: InterruptMethod = .automatic) -> InterruptResult {
        guard let transport, [.busy, .question, .debugger].contains(state) else { return .nothingToInterrupt }
        for job in queue {
            job.statements.forEach { job.sink.yield(.skipped($0)) }
            finish(job, .interrupted)
        }
        queue.removeAll()
        switch method {
        case .channel:
            return transport.interruptViaChannel() ? .channel : .noChannel
        case .signal:
            transport.interruptViaSignal()
            return .signal
        case .automatic:
            if transport.interruptViaChannel() { return .channel }
            transport.interruptViaSignal()
            return .signal
        }
    }

    private func runNext() {
        guard current == nil, let transport else { return }
        guard !queue.isEmpty else {
            setState(lispMode ? .lisp : .idle)
            return
        }
        let job = queue.removeFirst()
        current = job
        sendStatement(job, via: transport)
    }

    private func sendStatement(_ job: CellJob, via transport: any MaximaTransport) {
        let statement = job.statements[job.next]
        if !lispMode {
            transport.send(GlueLisp.lineWidthLine(configuration.lineWidth))
            if job.id != lastCellID {
                transport.send(GlueLisp.cellIDLine(job.id))
                lastCellID = job.id
            }
        }
        statementText.removeAll()
        job.sink.yield(.started(index: job.next, statement))
        setState(.busy)
        if !lispMode, GlueLisp.isBreakCommand(statement) {
            // A break command prints the prompt `:lisp-quiet` blanked, so
            // whether one comes depends on what ran before (checked on
            // 5.50.0). Blank it for sure, then restore it with `:lisp`,
            // which prints no value for (values) and exactly one prompt.
            transport.send(":lisp-quiet nil\n")
            transport.send(statement.text + "\n")
            transport.send(":lisp (values)\n")
        } else {
            transport.send(statement.text + "\n")
        }
        // Maxima answers a :lisp-quiet line with no prompt (fixture 26), so
        // waiting for one would hang the cell: the statement ends here.
        if statement.terminator == .line && statement.text.hasPrefix(":lisp-quiet") {
            statementEnded(label: lastLabel)
        }
    }

    /// Ends the running statement at a main prompt.
    private func statementEnded(label: Int) {
        guard let job = current else { return }
        job.next += 1
        switch OutputClassifier.classify(statementText) {
        case .interrupted:
            job.sink.yield(.interrupted)
            job.sink.yield(.prompt(label: label))
            job.statements[job.next...].forEach { job.sink.yield(.skipped($0)) }
            finish(job, .interrupted)
        case .error(let kind, let message):
            job.sink.yield(.error(kind, message: message))
            job.sink.yield(.prompt(label: label))
            job.failure = job.failure ?? kind
            if configuration.abortCellOnError || job.next == job.statements.count {
                job.statements[job.next...].forEach { job.sink.yield(.skipped($0)) }
                finish(job, .failed(job.failure ?? kind))
            }
            if configuration.abortCellOnError { cancelQueue() }
        case nil:
            job.sink.yield(.prompt(label: label))
            if job.next == job.statements.count { finish(job, job.failure.map { .failed($0) } ?? .completed) }
        }
        statementText.removeAll()
        if current === job, let transport {
            sendStatement(job, via: transport)
        } else {
            runNext()
        }
    }

    /// Abort on error: the cells waiting behind the failed one are not run.
    private func cancelQueue() {
        for job in queue {
            job.statements.forEach { job.sink.yield(.skipped($0)) }
            finish(job, .cancelled)
        }
        queue.removeAll()
    }

    /// Settings › Abort on Error, for the cells evaluated from now on.
    public func setAbortOnError(_ on: Bool) {
        configuration.abortCellOnError = on
    }

    private func finish(_ job: CellJob, _ outcome: CellOutcome) {
        job.sink.yield(.finished(outcome))
        job.sink.finish()
        if current === job { current = nil }
    }

    private func failAllCells(_ reason: String) {
        for job in ([current].compactMap { $0 } + queue) {
            job.statements[job.next...].dropFirst(job === current ? 1 : 0).forEach { job.sink.yield(.skipped($0)) }
            finish(job, .sessionDied(reason))
        }
        current = nil
        queue.removeAll()
        statementText.removeAll()
    }

    // MARK: - Input from Maxima

    private func handle(_ event: TransportEvent, generation gen: Int) async {
        guard gen == generation else { return }
        switch event {
        case .data(let data):
            for e in scanner.feed(data) { handle(e) }
        case .interruptChannelReady:
            interruptChannelReady = true
            eventSink.yield(.interruptChannelReady)
        case .slowStart:
            eventSink.yield(.slowStart)
        case .closed, .exited:
            for e in scanner.flush() { handle(e) }
            if let transport {
                await abandon(transport, reason: event == .closed ? String(localized: "Maxima closed the connection") : String(localized: "Maxima exited"))
            }
        }
    }

    private func handle(_ event: ScannerEvent) {
        switch state {
        case .dead, .starting:
            return
        case .authenticating:
            authenticate(event)
            return
        default:
            break
        }
        switch event {
        case .prompt(let content):
            prompt(PromptClassifier.classify(content))
        case .math(let xml):
            if let job = current { job.sink.yield(.math(xml)) } else { eventSink.yield(.output(event)) }
        case .text(let line):
            if let job = current {
                statementText.append(line)
                job.sink.yield(.text(line))
            } else {
                eventSink.yield(.output(event))
            }
        case .tag(name: "wxasync", let content):
            routeAsync(content)
        case .tag(let name, let content) where ["statusbar", "wxxml-asciimath", "worksheetexport"].contains(name):
            if let job = current { job.sink.yield(.tag(name: name, content: content)) }
            else { eventSink.yield(.tag(name: name, content: content)) }
        case .tag(let name, let content):
            if name == "variables", let promised = Self.channelPromise(in: content) {
                interruptChannelPromised = promised
            }
            eventSink.yield(.tag(name: name, content: content))
        }
    }

    /// Drops everything until the echoed token matches.
    private func authenticate(_ event: ScannerEvent) {
        let content: String
        switch event {
        case .tag("wxxml-key", let c): content = "<wxxml-key>\(c)</wxxml-key>"
        case .tag("suppressOutput", let c): content = c
        default: return
        }
        guard let start = content.range(of: "<wxxml-key>"),
              let end = content.range(of: "</wxxml-key>", range: start.upperBound..<content.endIndex) else { return }
        let echoed = String(content[start.upperBound..<end.lowerBound])
        guard echoed == token, let transport else {
            authWaiter?.resolve(.failure(.authenticationFailed("Maxima echoed a different token")))
            return
        }
        transport.controlAuthenticated()
        setState(.configuring)
        for line in GlueLisp.setupLines(gnuplotPath: configuration.gnuplotPath, port: transport.port,
                                        token: token, tempDirectory: transport.tempDirectory) {
            transport.send(line)
        }
        transport.send(GlueLisp.macsimaCommand())
        for line in configuration.additionalSetupLines { transport.send(line) }
        setState(.idle)
        authWaiter?.resolve(.success(()))
    }

    private func prompt(_ kind: PromptKind) {
        switch kind {
        case .main(let label):
            lispMode = false
            lastLabel = label
            if current != nil { statementEnded(label: label) } else { setState(.idle) }
        case .lisp:
            lispMode = true
            if current != nil { statementEnded(label: 0) } else { setState(.lisp) }
        case .debugger(let level):
            if lispMode {   // every prompt counts as main in Lisp mode (MaximaProtocol.h)
                if current != nil { statementEnded(label: 0) }
                return
            }
            current?.sink.yield(.debugger(level: level))
            setState(.debugger)
        case .question(let content):
            if lispMode {
                if current != nil { statementEnded(label: 0) }
                return
            }
            current?.sink.yield(.question(content))
            setState(.question)
        }
    }

    /// `<wxasync><id>ID</id>payload</wxasync>`: to the open cell with that
    /// ID, or to `events` when it has finished.
    private func routeAsync(_ content: String) {
        var id = ""
        var payload = content
        if let start = content.range(of: "<id>"), let end = content.range(of: "</id>", range: start.upperBound..<content.endIndex) {
            id = String(content[start.upperBound..<end.lowerBound])
            payload = String(content[end.upperBound...])
        }
        if let job = ([current].compactMap { $0 } + queue).first(where: { $0.id == id }) {
            job.sink.yield(.async(payload))
        } else {
            eventSink.yield(.async(cellID: id, content: payload))
        }
    }

    static func channelPromise(in variables: String) -> Bool? {
        let key = "<name>*wx-interrupt-channel-available*</name><value>"
        guard let r = variables.range(of: key) else { return nil }
        return variables[r.upperBound...].hasPrefix("true")
    }

    private func setState(_ new: SessionState) {
        guard new != state else { return }
        state = new
        eventSink.yield(.state(new))
        if new == .idle { sendQueries() }
    }

    // MARK: - Background queries

    /// `:lisp-quiet` lines waiting for Maxima to be idle. Sent while a
    /// question waits, one would be read as the answer.
    private var queries: [String] = []

    /// Looks `topic` up in Maxima's manual. The reply comes as
    /// `.tag("macsima-help", ...)` (see `MaximaHelp.parse`), once Maxima is idle.
    public func help(_ topic: String) {
        query(":lisp-quiet (macsima-help \(GlueLisp.lispString(topic)))\n")
    }

    /// The values of watched variables, as `.tag("macsima-values", ...)`
    /// (see `MaximaVariables.parse`), once Maxima is idle.
    public func values(of names: [String]) {
        guard !names.isEmpty else { return }
        query(":lisp-quiet (macsima-values '(\(names.map(GlueLisp.lispString).joined(separator: " "))))\n")
    }

    /// Sets a Maxima option such as `debugmode` the way `option: value` does
    /// (running its assign function), without an input label; once Maxima is idle.
    public func setOption(_ name: String, _ value: Bool) {
        guard name.wholeMatch(of: /[a-z_0-9]+/) != nil else { return }
        query(":lisp-quiet (meval '((msetq) $\(name) \(value ? "t" : "nil")))\n")
    }

    /// The user's variables (Maxima's `values`), as `.tag("macsima-variable-names", ...)`.
    public func variableNames() {
        query(":lisp-quiet (macsima-variable-names)\n")
    }

    private func query(_ line: String) {
        queries.append(line)
        sendQueries()
    }

    private func sendQueries() {
        guard state == .idle, current == nil, queue.isEmpty, let transport else { return }
        let lines = queries
        queries.removeAll()
        for line in lines { transport.send(line) }
    }
}
