// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// How to start and drive Maxima.
public struct MaximaConfiguration: Sendable {
    public var maximaPath = "/opt/homebrew/bin/maxima"
    public var gnuplotPath = "/opt/homebrew/bin/gnuplot"
    /// Sets `MAXIMA_INITIAL_FOLDER`; Maxima reads it once at startup.
    public var initialFolder: String?
    /// Sent as `linel` before every statement.
    public var lineWidth = 80
    /// When a statement fails, stop: the rest of its cell and the cells
    /// queued after it are not run (wxMaxima's "abort on error", which
    /// clears its evaluation queue). Off, everything goes on.
    public var abortCellOnError = true
    /// Launch attempts when Maxima exits before connecting.
    public var startAttempts = 3
    /// A `.slowStart` event is sent when Maxima has not connected after this long.
    public var slowStartWarning: Duration = .seconds(5)
    /// Give up on a launch attempt after this long without a connection.
    public var connectTimeout: Duration = .seconds(30)
    /// Give up when the echoed token has not arrived after this long.
    public var authenticationTimeout: Duration = .seconds(30)
    /// Time between SIGTERM and SIGKILL when killing Maxima.
    public var killGrace: Duration = .seconds(2)
    /// Replaces the bundled `wxMathML.lisp` (tests).
    public var glueSource: String?
    /// Lines sent after the standard setup lines, without waiting for a
    /// prompt; each should be a `:lisp-quiet` line ending in a newline. The
    /// app uses it for `(setq $wxplot_pngcairo t)` when gnuplot has pngcairo.
    public var additionalSetupLines: [String] = []

    public init() {}
}

public enum MaximaError: Error, Equatable, Sendable, CustomStringConvertible {
    case glueMissing
    case maximaNotFound(String)
    case spawnFailed(String)
    case listenFailed(String)
    /// Maxima exited before connecting on every attempt.
    case failedToStart(attempts: Int, logTail: String)
    case connectTimeout(Duration)
    case authenticationFailed(String)
    case notRunning
    case busy(String)
    case noQuestion
    case split(SplitError)

    public var description: String {
        switch self {
        case .glueMissing: String(localized: "wxMathML.lisp is missing from the MaximaKit bundle.")
        case .maximaNotFound(let path): String(localized: "No Maxima executable at \(path).")
        case .spawnFailed(let why): String(localized: "Could not start Maxima: \(why).")
        case .listenFailed(let why): String(localized: "Could not open the local socket for Maxima: \(why).")
        case let .failedToStart(attempts, tail):
            String(localized: "Maxima exited before connecting, \(attempts) times. Its last output:\n\(tail)")
        case .connectTimeout(let d): String(localized: "Maxima did not connect within \(String(describing: d)).")
        case .authenticationFailed(let why): String(localized: "Maxima did not authenticate: \(why).")
        case .notRunning: String(localized: "Maxima is not running.")
        case .busy(let why): why
        case .noQuestion: String(localized: "Maxima is not asking a question.")
        case .split(let error): error.description
        }
    }
}
