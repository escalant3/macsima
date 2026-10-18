// SPDX-License-Identifier: GPL-2.0-or-later

import Darwin
import Foundation

/// What a transport reports to the session.
public enum TransportEvent: Sendable, Equatable {
    /// Bytes from the control connection.
    case data(Data)
    /// The second connection sent the right token; interrupts can use it.
    case interruptChannelReady
    /// Maxima has not connected within `slowStartWarning`.
    case slowStart
    /// The control connection closed.
    case closed
    /// The Maxima process exited (described). The stream ends after this.
    case exited(String)
}

/// One Maxima process and its sockets. The session talks only to this
/// protocol, so tests can replay recorded transcripts instead.
public protocol MaximaTransport: AnyObject, Sendable {
    /// Everything the transport reports, from creation until termination.
    var events: AsyncStream<TransportEvent> { get }
    /// Starts Maxima and returns once its control connection is accepted.
    func launch(token: String) async throws(MaximaError)
    /// The port the interrupt channel must dial.
    var port: UInt16 { get }
    /// Maxima's private temp folder (`maxima_tempdir`).
    var tempDirectory: String { get }
    /// The process group, while it runs.
    var processGroup: pid_t? { get }
    /// Writes to the control connection.
    func send(_ text: String)
    /// From now on a new connection is an interrupt-channel candidate.
    func controlAuthenticated()
    /// Writes `interrupt` on the channel. False if there is no channel.
    func interruptViaChannel() -> Bool
    /// SIGINT to the process group.
    func interruptViaSignal()
    /// Closes the sockets, kills the process group (SIGTERM, then SIGKILL
    /// after the grace period) and deletes the temp folder. Idempotent.
    func terminate() async
}
