// SPDX-License-Identifier: GPL-2.0-or-later

import Darwin
import Foundation
import Synchronization

/// A Maxima child process in its own process group.
///
/// Foundation's `Process` cannot make the child a group leader, so this uses
/// posix_spawn with POSIX_SPAWN_SETPGROUP. Homebrew's `maxima` script `exec`s
/// SBCL, so the PID is the Lisp itself and its group also holds any gnuplot
/// it starts. A dispatch source reaps the child when it exits.
final class MaximaProcess: Sendable {
    let pid: pid_t
    /// The process group, equal to `pid`.
    var group: pid_t { pid }

    private let source: any DispatchSourceProcess
    private let exit = ExitBox()

    /// Starts `path` with `arguments`. stdin is /dev/null, stdout and stderr
    /// go to `logPath`. `onExit` runs once, on a background queue, with the
    /// raw wait status.
    init(path: String, arguments: [String], environment: [String: String], logPath: String,
         onExit: @escaping @Sendable (Int32) -> Void) throws(MaximaError) {
        guard FileManager.default.isExecutableFile(atPath: path) else { throw .maximaNotFound(path) }
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        // A child inherits the parent's signal mask and ignored signals. The
        // test runner, for one, blocks SIGTERM, which made Maxima ignore the
        // kill sequence; start the child with an empty mask and defaults.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                               | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attr, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attr, &noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        sigdelset(&allSignals, SIGKILL)
        sigdelset(&allSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attr, &allSignals)
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, logPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        defer {
            posix_spawnattr_destroy(&attr)
            posix_spawn_file_actions_destroy(&actions)
        }
        let cArgv = ([path] + arguments).map { strdup($0) } + [nil]
        let cEnv = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (cArgv + cEnv).forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, path, &actions, &attr, cArgv, cEnv)
        guard rc == 0 else { throw .spawnFailed(String(cString: strerror(rc))) }
        pid = child
        let spawned = child

        source = DispatchSource.makeProcessSource(identifier: spawned, eventMask: .exit,
                                                  queue: .global(qos: .userInitiated))
        let box = exit
        let reap: @Sendable () -> Void = {
            var raw: Int32 = 0
            let r = waitpid(spawned, &raw, WNOHANG)
            guard r == spawned || (r == -1 && errno == ECHILD) else { return }
            let first = box.status.withLock { s -> Bool in
                guard s == nil else { return false }
                s = raw
                return true
            }
            guard first else { return }
            onExit(raw)
        }
        source.setEventHandler(handler: reap)
        source.activate()
        reap()   // in case it exited before the source was armed
    }

    deinit { source.cancel() }

    var hasExited: Bool { exit.status.withLock { $0 != nil } }

    /// Sends `signal` to the whole process group (the Lisp and any gnuplot).
    func signalGroup(_ signal: Int32) {
        killpg(group, signal)
    }

    /// Waits for the exit, up to `timeout`. Returns the wait status, or nil.
    /// Polls: this only runs on the kill path, where 20 ms does not matter.
    func waitForExit(timeout: Duration) async -> Int32? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let s = exit.status.withLock({ $0 }) { return s }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return exit.status.withLock { $0 }
    }

    /// True while any process in the group is alive.
    static func groupAlive(_ group: pid_t) -> Bool {
        killpg(group, 0) == 0 || errno == EPERM
    }
}

/// The exit status, shared between the process and its dispatch handler.
private final class ExitBox: Sendable {
    let status = Mutex<Int32?>(nil)
}

/// Describes a raw wait status.
func describeExit(_ status: Int32) -> String {
    let low = status & 0x7F
    if low == 0 { return "exit code \((status >> 8) & 0xFF)" }
    return "signal \(low)"
}
