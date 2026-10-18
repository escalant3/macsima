// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The session's state machine (BOOTSTRAP.md, "State machine").
public enum SessionState: String, Sendable, Equatable {
    /// Spawning Maxima and waiting for it to connect.
    case starting
    /// The glue Lisp is sent; all output is dropped until the token is echoed.
    case authenticating
    /// Sending the setup lines.
    case configuring
    /// Waiting at a main prompt with nothing to send.
    case idle
    /// A statement or an answer is being evaluated.
    case busy
    /// Maxima asked a question; `answer(_:)` replies.
    case question
    /// The Maxima debugger, `(dbm:N)`; `answer(_:)` sends debugger commands.
    case debugger
    /// Idle in the Lisp REPL after `to_lisp()`.
    case lisp
    /// No Maxima process (before `start()`, after a kill or a crash).
    case dead
}

/// How an error was recognized in Maxima's plain-text output.
public enum ErrorKind: String, Sendable, Equatable {
    /// A line containing `-- an error.` (merror, error(), and the debugger variant).
    case maxima
    /// A line starting `incorrect syntax:`.
    case syntax
    /// `Maxima encountered a Lisp error:` (not an interrupt).
    case lisp
}

public enum CellOutcome: Sendable, Equatable, CustomStringConvertible {
    case completed
    case failed(ErrorKind)
    case interrupted
    case sessionDied(String)

    public var description: String {
        switch self {
        case .completed: "completed"
        case .failed(let kind): "failed (\(kind.rawValue) error)"
        case .interrupted: "interrupted"
        case .sessionDied(let why): "session died (\(why))"
        }
    }
}

/// What happens while one cell is evaluated, in order.
public enum CellEvent: Sendable, Equatable {
    /// The statement at `index` was sent.
    case started(index: Int, Statement)
    /// A math chunk (raw XML).
    case math(String)
    /// A line of plain text (print output, errors, `display2d:false` results).
    case text(String)
    /// Maxima asks a question (raw prompt content); answer with `answer(_:)`.
    case question(String)
    /// Maxima entered its debugger.
    case debugger(level: Int)
    /// The statement failed. `message` is the error's plain text.
    case error(ErrorKind, message: String)
    /// The statement was interrupted.
    case interrupted
    /// Not sent, because an earlier statement failed or was interrupted.
    case skipped(Statement)
    /// The statement finished at a main prompt with this input label (0 in Lisp mode).
    case prompt(label: Int)
    /// Background output from `wxasync` addressed to this cell (raw XML).
    case async(String)
    /// Another tag (`statusbar`, `wxxml-asciimath`, `worksheetexport`) during this cell.
    case tag(name: String, content: String)
    /// Always the last event.
    case finished(CellOutcome)
}

/// Things not tied to a running cell.
public enum SessionEvent: Sendable, Equatable {
    case state(SessionState)
    /// Maxima has not connected after `slowStartWarning`.
    case slowStart
    case interruptChannelReady
    /// `variables`, `wxxml-symbols` and the other session-wide tags.
    case tag(name: String, content: String)
    /// `wxasync` output for a cell whose stream has finished.
    case async(cellID: String, content: String)
    /// Output while no statement was running.
    case output(ScannerEvent)
    /// Maxima went away (crash, `quit()`, kill).
    case died(String)
}

public enum InterruptMethod: Sendable, Equatable {
    /// The interrupt channel if it is up, otherwise SIGINT.
    case automatic
    case channel
    case signal
}

/// What `interrupt` did.
public enum InterruptResult: Sendable, Equatable {
    case channel
    case signal
    /// Nothing was running.
    case nothingToInterrupt
    /// `.channel` was asked for but there is no channel.
    case noChannel
}
