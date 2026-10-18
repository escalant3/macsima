// SPDX-License-Identifier: GPL-2.0-or-later

import Darwin
import Foundation
import Network
import Synchronization

/// The real transport: a loopback listener plus a spawned `maxima -s <port>`.
///
/// Maxima is the client: the listener must be up before the spawn. The first
/// connection is the control connection. Until the session reports it
/// authenticated, any further connection is closed; afterwards one more
/// connection may become the interrupt channel, but only once its first line
/// equals the token. All mutable state sits behind one mutex; Network
/// callbacks run on a private serial queue.
public final class ProcessTransport: MaximaTransport {
    public let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let configuration: MaximaConfiguration
    private let queue = DispatchQueue(label: "MaximaKit.ProcessTransport")
    public let tempDirectory: String
    private let temp: SessionTempDirectory

    private struct State {
        var listener: NWListener?
        var port: UInt16 = 0
        var process: MaximaProcess?
        var control: NWConnection?
        var authenticated = false
        var interrupt: NWConnection?
        var interruptBuffer = Data()
        var interruptReady = false
        var connectWaiter: OneShot<ConnectOutcome>?
        var terminated = false
        var lispPIDs: [pid_t] = []
    }
    private let state = Mutex(State())

    enum ConnectOutcome: Sendable { case connected, exited(Int32), timeout }

    public init(configuration: MaximaConfiguration) throws(MaximaError) {
        self.configuration = configuration
        temp = try SessionTempDirectory.create()
        tempDirectory = temp.path
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public var port: UInt16 { state.withLock { $0.port } }
    public var processGroup: pid_t? { state.withLock { $0.process?.group } }

    public func launch(token: String) async throws(MaximaError) {
        channelToken.withLock { $0 = token }
        var lastTail = ""
        for _ in 1...max(1, configuration.startAttempts) {
            try await startListener()
            let waiter = OneShot<ConnectOutcome>()
            state.withLock { $0.connectWaiter = waiter }
            let process = try spawn(token: token, waiter: waiter)
            state.withLock {
                $0.process = process
                $0.lispPIDs.append(process.pid)
            }
            OrphanGuard.register(process.group)

            let slow = Task { [continuation, configuration] in
                try await Task.sleep(for: configuration.slowStartWarning)
                continuation.yield(.slowStart)
            }
            let timeout = Task { [configuration] in
                try await Task.sleep(for: configuration.connectTimeout)
                waiter.resolve(.timeout)
            }
            let outcome = await waiter.wait()
            slow.cancel()
            timeout.cancel()
            switch outcome {
            case .connected:
                return
            case .timeout:
                await terminate()
                throw .connectTimeout(configuration.connectTimeout)
            case .exited:
                lastTail = temp.logTail()
                process.signalGroup(SIGKILL)   // anything it left in its group
                OrphanGuard.unregister(process.group)
                state.withLock {
                    $0.listener?.cancel()
                    $0.listener = nil
                    $0.process = nil
                }
            }
        }
        await terminate()
        throw .failedToStart(attempts: configuration.startAttempts, logTail: lastTail)
    }

    private func startListener() async throws(MaximaError) {
        let params = NWParameters.tcp
        // Maxima's -s dials "localhost" and connected over IPv4 in Phase 0;
        // the interrupt channel dials the literal 127.0.0.1 it is given.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener: NWListener
        do { listener = try NWListener(using: params) } catch {
            throw .listenFailed("\(error)")
        }
        let ready = OneShot<Result<UInt16, MaximaError>>()
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.resolve(.success(listener.port?.rawValue ?? 0))
            case .failed(let error): ready.resolve(.failure(.listenFailed("\(error)")))
            case .cancelled: ready.resolve(.failure(.listenFailed("cancelled")))
            default: break
            }
        }
        state.withLock { $0.listener = listener }
        listener.start(queue: queue)
        let port = try await ready.wait().get()
        state.withLock { $0.port = port }
    }

    private func spawn(token: String, waiter: OneShot<ConnectOutcome>) throws(MaximaError) -> MaximaProcess {
        var env = ProcessInfo.processInfo.environment
        env["MAXIMA_AUTH_CODE"] = token
        env["TMPDIR"] = temp.path + "/"
        if let folder = configuration.initialFolder { env["MAXIMA_INITIAL_FOLDER"] = folder }
        let port = state.withLock { $0.port }
        return try MaximaProcess(
            path: configuration.maximaPath, arguments: ["-s", String(port)], environment: env,
            logPath: temp.logPath
        ) { [weak self] status in
            waiter.resolve(.exited(status))
            self?.processExited(status)
        }
    }

    private func processExited(_ status: Int32) {
        let connected = state.withLock { $0.control != nil }
        guard connected else { return }   // launch() handles exits before connecting
        continuation.yield(.exited(describeExit(status)))
        continuation.finish()
    }

    private func accept(_ connection: NWConnection) {
        enum Role { case control, interruptCandidate, reject }
        let role: Role = state.withLock { s in
            if s.terminated { return .reject }
            if s.control == nil { s.control = connection; return .control }
            if s.authenticated && s.interrupt == nil { s.interrupt = connection; return .interruptCandidate }
            return .reject
        }
        switch role {
        case .control:
            connection.start(queue: queue)
            receiveControl(connection)
            state.withLock { $0.connectWaiter }?.resolve(.connected)
        case .interruptCandidate:
            connection.start(queue: queue)
            receiveInterrupt(connection)
        case .reject:
            connection.cancel()
        }
    }

    private func receiveControl(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data, !data.isEmpty { continuation.yield(.data(data)) }
            if done || error != nil {
                continuation.yield(.closed)
            } else {
                receiveControl(c)
            }
        }
    }

    private func receiveInterrupt(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            guard let self else { return }
            enum Verdict { case wait, ready, wrong, nothing }
            let verdict: Verdict = state.withLock { s in
                guard !s.interruptReady else { return .nothing }
                if let data { s.interruptBuffer.append(data) }
                guard let nl = s.interruptBuffer.firstIndex(of: 0x0A) else {
                    return s.interruptBuffer.count > 4096 ? .wrong : .wait
                }
                let line = String(decoding: s.interruptBuffer[..<nl], as: UTF8.self).trimmingWhitespace
                guard line == channelToken.withLock({ $0 }) else { return .wrong }
                s.interruptReady = true
                return .ready
            }
            switch verdict {
            case .ready: continuation.yield(.interruptChannelReady)
            case .wrong:
                c.cancel()
                state.withLock { s in
                    s.interrupt = nil
                    s.interruptBuffer.removeAll()
                }
                return
            case .wait, .nothing: break
            }
            if !(done || error != nil) { receiveInterrupt(c) }
        }
    }

    /// The token the interrupt channel must present; set by `launch`.
    private let channelToken = Mutex("")

    public func send(_ text: String) {
        let control = state.withLock { $0.control }
        control?.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }

    public func controlAuthenticated() {
        state.withLock { $0.authenticated = true }
    }

    public func interruptViaChannel() -> Bool {
        let channel = state.withLock { $0.interruptReady ? $0.interrupt : nil }
        guard let channel else { return false }
        channel.send(content: Data("interrupt\n".utf8), completion: .contentProcessed { _ in })
        return true
    }

    public func interruptViaSignal() {
        state.withLock { $0.process }?.signalGroup(SIGINT)
    }

    public func terminate() async {
        let (process, connections, listener, pids, first) = state.withLock { s in
            defer {
                s.terminated = true
                s.control = nil
                s.interrupt = nil
                s.listener = nil
            }
            return (s.process, [s.control, s.interrupt].compactMap { $0 }, s.listener, s.lispPIDs, !s.terminated)
        }
        connections.forEach { $0.cancel() }
        listener?.cancel()
        if let process {
            process.signalGroup(SIGTERM)
            if await process.waitForExit(timeout: configuration.killGrace) == nil {
                process.signalGroup(SIGKILL)
                _ = await process.waitForExit(timeout: .seconds(2))
            }
            // gnuplot or another child may outlive the Lisp in the group.
            if MaximaProcess.groupAlive(process.group) { process.signalGroup(SIGKILL) }
            OrphanGuard.unregister(process.group)
        }
        if first {
            temp.remove(lispPIDs: pids)
            continuation.finish()
        }
    }
}

/// A value delivered once, to one waiter, no matter who resolves first.
final class OneShot<T: Sendable>: Sendable {
    private let state = Mutex<(value: T?, waiter: CheckedContinuation<T, Never>?)>((nil, nil))

    func resolve(_ value: T) {
        let waiter = state.withLock { s -> CheckedContinuation<T, Never>? in
            guard s.value == nil else { return nil }
            s.value = value
            defer { s.waiter = nil }
            return s.waiter
        }
        waiter?.resume(returning: value)
    }

    func wait() async -> T {
        await withCheckedContinuation { c in
            let ready = state.withLock { s -> T? in
                if s.value == nil { s.waiter = c }
                return s.value
            }
            if let ready { c.resume(returning: ready) }
        }
    }
}
