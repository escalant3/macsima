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
    /// Stop the rest of a cell when one of its statements fails.
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
        case .glueMissing: "wxMathML.lisp is missing from the MaximaKit bundle."
        case .maximaNotFound(let path): "No Maxima executable at \(path)."
        case .spawnFailed(let why): "Could not start Maxima: \(why)."
        case .listenFailed(let why): "Could not open the local socket for Maxima: \(why)."
        case let .failedToStart(attempts, tail):
            "Maxima exited before connecting, \(attempts) times. Its last output:\n\(tail)"
        case .connectTimeout(let d): "Maxima did not connect within \(d)."
        case .authenticationFailed(let why): "Maxima did not authenticate: \(why)."
        case .notRunning: "Maxima is not running."
        case .busy(let why): why
        case .noQuestion: "Maxima is not asking a question."
        case .split(let error): error.description
        }
    }
}
