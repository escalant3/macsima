// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Synchronization
@testable import MaximaKit

/// Plays a recorded glue transcript back to a session.
///
/// The transcript is cut into segments: the startup output (through the
/// second `</variables>`), then one segment per `</PROMPT>`. Each segment is
/// released by a trigger taken from the scenario file: a statement or answer
/// send, an interrupt through the channel, or SIGINT. `:lisp-quiet` lines
/// (prelude and setup) and `!send` lines release nothing. When a trigger finds no segment left,
/// the connection closes, which is what `quit();` does. Data goes out in
/// random chunk sizes so the scanner sees split reads.
final class ReplayTransport: MaximaTransport {
    enum Trigger: String, Sendable { case send, interrupt, signal }

    let events: AsyncStream<TransportEvent>
    private let sink: AsyncStream<TransportEvent>.Continuation
    let port: UInt16 = 4242
    let tempDirectory = "/tmp/replay-not-real"
    var processGroup: pid_t? { nil }

    private struct State {
        var startup: Data
        var segments: [(Trigger, Data)]
        var sent: [String] = []
        var mismatches: [String] = []
        var rng: SplitMix64
        var startupSent = false
        var interruptPaths: [Trigger] = []
        var terminated = false
    }
    private let state: Mutex<State>
    private let hasChannel: Bool

    init(startup: Data, segments: [(Trigger, Data)], hasChannel: Bool = true, seed: UInt64 = 7) {
        state = Mutex(State(startup: startup, segments: segments, rng: SplitMix64(state: seed)))
        self.hasChannel = hasChannel
        (events, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Builds a replay of `glue/<name>` from its recording and scenario.
    static func fixture(_ name: String, hasChannel: Bool = true, seed: UInt64 = 7) throws -> ReplayTransport {
        let (startup, pieces) = try split(name)
        let triggers = try scenarioTriggers(name)
        var segments: [(Trigger, Data)] = []
        for (i, piece) in pieces.enumerated() {
            segments.append((i < triggers.count ? triggers[i] : .send, piece))
        }
        return ReplayTransport(startup: startup, segments: segments, hasChannel: hasChannel, seed: seed)
    }

    /// The startup output and the per-prompt segments of `glue/<name>`.
    static func split(_ name: String) throws -> (startup: Data, pieces: [Data]) {
        let bytes = [UInt8](try Fixtures.received(.glue, name))
        let variablesEnd = Array("</variables>".utf8)
        let promptEnd = Array("</PROMPT>".utf8)
        var cut = 0
        for _ in 0..<2 { cut = (bytes.firstRange(of: variablesEnd, from: cut)?.upperBound) ?? cut }
        var pieces: [Data] = []
        var from = cut
        while let r = bytes.firstRange(of: promptEnd, from: from) {
            pieces.append(Data(bytes[from..<r.upperBound]))
            from = r.upperBound
        }
        if from < bytes.count, var last = pieces.popLast() {   // trailing bytes ride with the last prompt
            last.append(contentsOf: bytes[from...])
            pieces.append(last)
        }
        return (Data(bytes[..<cut]), pieces)
    }

    /// The triggers a scenario's lines produce, in order.
    static func scenarioTriggers(_ name: String) throws -> [Trigger] {
        try scenarioLines(name).compactMap { line in
            if line.hasPrefix("!interrupt") { return .interrupt }
            if line.hasPrefix("!sigint") { return .signal }
            if line.hasPrefix("!send ") { return nil }   // its output ends after a later trigger
            if line.hasPrefix("!") { return nil }
            return .send
        }
    }

    static func scenarioLines(_ name: String) throws -> [String] {
        let dir = Fixtures.transcripts.appending(path: "scenarios")
        let file = [name + ".glue.scn", name + ".scn"].map { dir.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }!
        return try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
    }

    var sent: [String] { state.withLock { $0.sent } }
    var mismatches: [String] { state.withLock { $0.mismatches } }
    var interruptPaths: [Trigger] { state.withLock { $0.interruptPaths } }

    func launch(token: String) async throws(MaximaError) {}

    func send(_ text: String) {
        let release: Data? = state.withLock { s in
            s.sent.append(text)
            if !s.startupSent {
                s.startupSent = true
                return s.startup
            }
            if text.hasPrefix(":lisp-quiet ") { return nil }
            return pop(.send, &s)
        }
        deliver(release)
    }

    func controlAuthenticated() {
        if hasChannel { sink.yield(.interruptChannelReady) }
    }

    func interruptViaChannel() -> Bool {
        guard hasChannel else { return false }
        let release = state.withLock { s in
            s.interruptPaths.append(.interrupt)
            return pop(.interrupt, &s)
        }
        deliver(release)
        return true
    }

    func interruptViaSignal() {
        let release = state.withLock { s in
            s.interruptPaths.append(.signal)
            return pop(.signal, &s)
        }
        deliver(release)
    }

    func terminate() async {
        let first = state.withLock { s in defer { s.terminated = true }; return !s.terminated }
        if first { sink.finish() }
    }

    /// Takes the next segment if `trigger` is what releases it. An empty
    /// `Data` means: nothing left, close the connection.
    private func pop(_ trigger: Trigger, _ s: inout State) -> Data? {
        guard let (want, data) = s.segments.first else { return Data() }
        guard want == trigger else {
            // A statement sent while the next segment waits for an interrupt
            // is the long computation that interrupt will stop.
            if trigger == .send && want != .send { return nil }
            s.mismatches.append("got \(trigger), next segment wants \(want)")
            return nil
        }
        s.segments.removeFirst()
        return data
    }

    private func deliver(_ data: Data?) {
        guard let data else { return }
        if data.isEmpty {
            sink.yield(.closed)
            sink.yield(.exited("exit code 0"))
            sink.finish()
            return
        }
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let n = state.withLock { s in Int.random(in: 1...4096, using: &s.rng) }
            let end = min(bytes.count, i + n)
            sink.yield(.data(Data(bytes[i..<end])))
            i = end
        }
    }
}

extension Array where Element == UInt8 {
    func firstRange(of needle: [UInt8], from: Int) -> Range<Int>? {
        guard needle.count <= count - from else { return nil }
        var i = from
        while i <= count - needle.count {
            if self[i..<(i + needle.count)].elementsEqual(needle) { return i..<(i + needle.count) }
            i += 1
        }
        return nil
    }
}
