// SPDX-License-Identifier: GPL-2.0-or-later
//
// Phase 0 feasibility spike (see docs/BOOTSTRAP.md, "Phase 0 spike").
// Listens on 127.0.0.1, spawns `maxima -s <port>`, accepts Maxima's connection
// and prints or records the raw bytes it sends. Not the engine: MaximaKit's
// actor-based session replaces this in Phase 1.
//
// Usage:
//   maxima-spike [--glue <wxMathML.lisp>]
//       send integrate(sin(x), x); and print everything Maxima sends
//   maxima-spike record <scenario> <out-base> [--glue <wxMathML.lisp>]
//       run a scenario file, write <out-base>.txt (bytes received, verbatim)
//       and <out-base>.sent.txt (bytes sent)
//
// Scenario lines are sent one at a time; after each the spike waits for a
// prompt, a pause in the output (a question), or a timeout. Directives:
//   !send <text>    send without waiting
//   !sleep <s>      wait
//   !wait <s>       timeout for the next reply (default 15)
//   !sigint         SIGINT to Maxima's process group
//   !interrupt      "interrupt" on the interrupt channel (glue mode)
//   # ...           comment

import Darwin
import Foundation
import Network

let maximaPath = "/opt/homebrew/bin/maxima"
let gnuplotPath = "/opt/homebrew/bin/gnuplot"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("maxima-spike: \(message)\n".utf8))
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("[spike] \(message)\n".utf8))
}

/// Builds the one-line `:lisp-quiet` command the way wxMaxima's
/// `wxMathML::GetCmd` (wxMathml.cpp) does: strip leading indentation and
/// `;` comments outside strings, join lines with spaces.
func glueCommand(lisp: String) -> String {
    var out = ""
    var inString = false
    for line in lisp.split(separator: "\n", omittingEmptySubsequences: true) {
        let chars = Array(line)
        var kept = ""
        var atLineStart = true
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if atLineStart && (ch == " " || ch == "\t") { i += 1; continue }
            atLineStart = false
            if ch == "\\" {
                kept.append(ch)
                i += 1
                if i < chars.count { kept.append(chars[i]) }
                i += 1
                continue
            }
            if ch == "\"" { inString.toggle() }
            if ch == ";" && !inString { break }
            kept.append(ch)
            i += 1
        }
        out += kept + " "
    }
    return ":lisp-quiet " + out + "\n"
}

/// All mutable state lives on `queue`; the driver on the main thread reads it
/// through `queue.sync`. That is what makes the unchecked conformance sound.
final class Spike: @unchecked Sendable {
    let queue = DispatchQueue(label: "maxima-spike")
    let token: String
    let glue: Bool
    let echo: Bool

    private var listener: NWListener?
    private var control: NWConnection?
    private var interruptChannel: NWConnection?
    private var interruptBuffer = Data()
    private(set) var interruptReady = false
    private(set) var pid: pid_t = 0
    private(set) var port: UInt16 = 0

    private(set) var received = Data()
    private(set) var sent = Data()
    private(set) var sinceSend = Data()
    private(set) var lastReceive = Date.distantPast
    private(set) var closed = false

    init(token: String, glue: Bool, echo: Bool) {
        self.token = token
        self.glue = glue
        self.echo = echo
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener
        let ready = DispatchSemaphore(value: 0)
        listener.newConnectionHandler = { [self] c in accept(c) }
        listener.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                port = listener.port?.rawValue ?? 0
                ready.signal()
            case .failed(let error):
                fail("listener failed: \(error)")
            default:
                break
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else { fail("listener not ready") }
        log("listening on 127.0.0.1:\(queue.sync { port })")
    }

    /// posix_spawn in its own process group, so signals reach the Lisp and
    /// any gnuplot it starts. Foundation's Process cannot set the group.
    func spawn(stdioLog: String) {
        let port = queue.sync { self.port }
        var env = ProcessInfo.processInfo.environment
        env["MAXIMA_AUTH_CODE"] = token
        let argv = [maximaPath, "-s", String(port)]
        let envp = env.map { "\($0.key)=\($0.value)" }

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, stdioLog, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        defer {
            posix_spawnattr_destroy(&attr)
            posix_spawn_file_actions_destroy(&actions)
        }

        let cArgv = argv.map { strdup($0) } + [nil]
        let cEnv = envp.map { strdup($0) } + [nil]
        defer { (cArgv + cEnv).forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, maximaPath, &actions, &attr, cArgv, cEnv)
        guard rc == 0 else { fail("posix_spawn: \(String(cString: strerror(rc)))") }
        queue.sync { pid = child }
        log("spawned \(argv.joined(separator: " ")) pid \(child)")
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        if control == nil {
            control = c
            log("control connection from \(c.endpoint)")
            receiveControl(c)
        } else if interruptChannel == nil {
            interruptChannel = c
            log("second connection from \(c.endpoint) (interrupt channel?)")
            receiveInterrupt(c)
        } else {
            log("unexpected extra connection; closing")
            c.cancel()
        }
    }

    private func receiveControl(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, error in
            if let data, !data.isEmpty {
                received.append(data)
                sinceSend.append(data)
                lastReceive = Date()
                if echo { FileHandle.standardOutput.write(data) }
            }
            if done || error != nil {
                closed = true
                log("control connection closed\(error.map { ": \($0)" } ?? "")")
            } else {
                receiveControl(c)
            }
        }
    }

    private func receiveInterrupt(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, done, error in
            if let data { interruptBuffer.append(data) }
            if !interruptReady, let nl = interruptBuffer.firstIndex(of: 0x0A) {
                let line = String(decoding: interruptBuffer[..<nl], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if line == token {
                    interruptReady = true
                    log("interrupt channel authenticated")
                } else {
                    log("interrupt channel sent a wrong token; closing")
                    c.cancel()
                    return
                }
            }
            if done || error != nil {
                log("interrupt channel closed")
            } else {
                receiveInterrupt(c)
            }
        }
    }

    func send(_ text: String, logAs: String? = nil) {
        queue.sync {
            sinceSend.removeAll()
            sent.append(Data((logAs ?? text).utf8))
            control?.send(content: Data(text.utf8), completion: .contentProcessed { error in
                if let error { log("send failed: \(error)") }
            })
        }
    }

    func sendInterrupt() {
        queue.sync {
            sent.append(Data("<!interrupt on interrupt channel>\n".utf8))
            guard interruptReady, let c = interruptChannel else {
                log("no authenticated interrupt channel")
                return
            }
            c.send(content: Data("interrupt\n".utf8), completion: .contentProcessed { _ in })
        }
    }

    func signal(_ sig: Int32) {
        let pid = queue.sync {
            sent.append(Data("<!signal \(sig) to process group>\n".utf8))
            return self.pid
        }
        if pid > 0 { killpg(pid, sig) }
    }

    func snapshot<T>(_ body: (Spike) -> T) -> T { queue.sync { body(self) } }

    /// True when the output since the last send ends in a main or question prompt.
    func sawPrompt() -> Bool {
        snapshot { s in
            let text = String(decoding: s.sinceSend, as: UTF8.self)
            if s.glue && text.contains("</PROMPT>") { return true }
            return text.range(of: #"\(%i\d+\) $"#, options: .regularExpression) != nil
        }
    }

    /// Waits for a prompt, or for output followed by `quiet` seconds of
    /// silence (questions in raw mode carry no marker), or for `timeout`.
    @discardableResult
    func waitForReply(timeout: TimeInterval, quiet: TimeInterval = 1.5) -> String {
        let start = Date()
        while true {
            if sawPrompt() { Thread.sleep(forTimeInterval: 0.2); return "prompt" }
            let (count, last, closed) = snapshot { ($0.sinceSend.count, $0.lastReceive, $0.closed) }
            if closed { return "closed" }
            if count > 0 && Date().timeIntervalSince(last) > quiet { return "quiet" }
            if Date().timeIntervalSince(start) > timeout { return "timeout" }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    func waitForConnection() {
        let start = Date()
        while snapshot({ $0.control == nil }) {
            if Date().timeIntervalSince(start) > 10 { fail("Maxima did not connect within 10 s") }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// The setup wxMaxima sends after connecting (MaximaEvaluator::SetupVariables),
    /// minus the help format and version strings this spike does not need.
    func sendGlue(lispPath: String) {
        guard let lisp = try? String(contentsOfFile: lispPath, encoding: .utf8) else {
            fail("cannot read \(lispPath)")
        }
        let cmd = glueCommand(lisp: lisp)
        send(cmd, logAs: "<:lisp-quiet wxMathML.lisp, \(cmd.utf8.count) bytes>\n")
        let port = snapshot { $0.port }
        for line in [
            ":lisp-quiet (setf $gnuplot_command \"\(gnuplotPath)\")\n",
            ":lisp-quiet (when (fboundp 'wx-open-interrupt-channel) (wx-open-interrupt-channel \"127.0.0.1\" \(port) \"\(token)\"))\n",
            ":lisp-quiet (ignore-errors (setf (symbol-value '*lisp-quiet-suppressed-prompt*) \"<PROMPT>(%i1)</PROMPT>\"))\n",
            ":lisp-quiet (setf *prompt-suffix* \"</PROMPT>\") (setf *prompt-prefix* \"<PROMPT>\") (setf $in_netmath nil) (setf $show_openplot t) \n",
        ] {
            send(line)
        }
    }

    func shutdown() {
        let pid = snapshot { $0.pid }
        guard pid > 0 else { return }
        snapshot { $0.control?.cancel(); $0.interruptChannel?.cancel() }
        killpg(pid, SIGTERM)
        var status: Int32 = 0
        for _ in 0..<100 {
            if waitpid(pid, &status, WNOHANG) == pid { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        log("Maxima ignored SIGTERM; sending SIGKILL")
        killpg(pid, SIGKILL)
        waitpid(pid, &status, 0)
    }
}

// MARK: - Command line

var args = Array(CommandLine.arguments.dropFirst())
var gluePath: String?
if let i = args.firstIndex(of: "--glue") {
    guard i + 1 < args.count else { fail("--glue needs a path") }
    gluePath = args[i + 1]
    args.removeSubrange(i...(i + 1))
}

let recording = args.first == "record"
if recording && args.count != 3 { fail("usage: maxima-spike record <scenario> <out-base> [--glue <lisp>]") }

let token = recording
    ? "PHASE0-TEST-TOKEN"   // fixed, so fixtures hold no real secret
    : (0..<64).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()

let spike = Spike(token: token, glue: gluePath != nil, echo: !recording)
signal(SIGPIPE, SIG_IGN)
try spike.start()
let outBase = recording ? args[2] : nil
spike.spawn(stdioLog: outBase.map { "\($0).stdio.txt" } ?? "/dev/null")
spike.waitForConnection()
log("first prompt: \(spike.waitForReply(timeout: 30))")

if let gluePath {
    spike.sendGlue(lispPath: gluePath)
    log("after glue: \(spike.waitForReply(timeout: 30, quiet: 2))")
    let key = spike.snapshot { String(decoding: $0.received, as: UTF8.self) }
        .contains("<wxxml-key>\(token)</wxxml-key>")
    log("auth token echoed: \(key)")
    log("interrupt channel ready: \(spike.snapshot { $0.interruptReady })")
}

if recording {
    guard let scenario = try? String(contentsOfFile: args[1], encoding: .utf8) else {
        fail("cannot read \(args[1])")
    }
    var timeout: TimeInterval = 15
    for line in scenario.split(separator: "\n").map(String.init) {
        if line.hasPrefix("#") || line.isEmpty { continue }
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "!send": spike.send(parts[1] + "\n")
        case "!sleep": Thread.sleep(forTimeInterval: Double(parts[1]) ?? 1)
        case "!wait": timeout = Double(parts[1]) ?? 15; continue
        case "!sigint": spike.signal(SIGINT); log("reply: \(spike.waitForReply(timeout: timeout))")
        case "!interrupt": spike.sendInterrupt(); log("reply: \(spike.waitForReply(timeout: timeout))")
        default:
            let started = Date()
            spike.send(line + "\n")
            let how = spike.waitForReply(timeout: timeout)
            log(String(format: "%@ -> %@ (%.2f s)", line, how, Date().timeIntervalSince(started)))
        }
        timeout = 15
    }
    let (received, sent) = spike.snapshot { ($0.received, $0.sent) }
    try received.write(to: URL(filePath: "\(outBase!).txt"))
    try sent.write(to: URL(filePath: "\(outBase!).sent.txt"))
    log("wrote \(received.count) bytes to \(outBase!).txt")
} else {
    spike.send("integrate(sin(x), x);\n")
    log("reply: \(spike.waitForReply(timeout: 30))")
}
spike.shutdown()
