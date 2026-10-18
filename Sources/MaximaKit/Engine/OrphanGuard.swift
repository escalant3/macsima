// SPDX-License-Identifier: GPL-2.0-or-later
//
// Same idea as wxMaxima's signal-safe child list (src/MaximaProcessManager.cpp);
// wxMaxima is Copyright (C) Andrej Vodopivec, Gunter Koenigsmann and the
// wxMaxima developers, GPL-2.0-or-later.

import Darwin
import Synchronization

/// Kills every running Maxima process group when the host gets SIGTERM,
/// SIGINT or SIGHUP.
///
/// Maxima runs in its own process group, so a Ctrl+C or a logout does not
/// reach it, and a Maxima busy computing only notices the closed socket when
/// it next reads. Without this, quitting the host would orphan it.
///
/// The handler may only use async-signal-safe calls and memory that never
/// moves: the groups live in a fixed C array that is allocated once, written
/// under a lock by `register`/`unregister`, and only read by the handler
/// (aligned 32-bit loads and stores are atomic on arm64). It cannot catch
/// SIGKILL; temp folders left behind are swept on the next start.
public enum OrphanGuard {
    static let capacity = 64

    /// Allocated on first use; `install()` touches it so the handler never runs the initializer.
    nonisolated(unsafe) private static let slots: UnsafeMutablePointer<pid_t> = {
        let p = UnsafeMutablePointer<pid_t>.allocate(capacity: capacity)
        p.initialize(repeating: 0, count: capacity)
        return p
    }()
    private static let lock = Mutex(())

    /// Installs the handlers. Call once from the app or command-line tool,
    /// not from a test runner.
    public static func install() {
        _ = slots
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = handler
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0
            sigaction(sig, &action, nil)
        }
    }

    public static func register(_ group: pid_t) {
        guard group > 0 else { return }
        lock.withLock { _ in
            for i in 0..<capacity where slots[i] == 0 {
                slots[i] = group
                return
            }
        }
    }

    public static func unregister(_ group: pid_t) {
        lock.withLock { _ in
            for i in 0..<capacity where slots[i] == group { slots[i] = 0 }
        }
    }

    /// The groups currently registered.
    public static var registered: [pid_t] {
        lock.withLock { _ in (0..<capacity).map { slots[$0] }.filter { $0 > 0 } }
    }

    private static let handler: @convention(c) (Int32) -> Void = { sig in
        for i in 0..<OrphanGuard.capacity {
            let group = OrphanGuard.slots[i]
            if group > 0 { killpg(group, SIGKILL) }
        }
        // Then die the way the signal would have killed us.
        signal(sig, SIG_DFL)
        raise(sig)
    }
}
