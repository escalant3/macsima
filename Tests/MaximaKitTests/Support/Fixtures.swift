// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The recorded transcripts in `Tests/Fixtures/transcripts` (see its README).
enum Fixtures {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures")
    static let transcripts = root.appending(path: "transcripts")

    /// The auth token every glue fixture was recorded with.
    static let token = "PHASE0-TEST-TOKEN"

    enum Mode: String, CaseIterable { case raw, glue }

    /// Scenario names (such as `04-error-division`) recorded in `mode`.
    static func names(_ mode: Mode) -> [String] {
        let dir = transcripts.appending(path: mode.rawValue)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files
            .filter { $0.hasSuffix(".txt") && !$0.hasSuffix(".sent.txt") && !$0.hasSuffix(".stdio.txt") }
            .map { String($0.dropLast(4)) }
            .sorted()
    }

    /// Every byte received on the control socket.
    static func received(_ mode: Mode, _ name: String) throws -> Data {
        try Data(contentsOf: transcripts.appending(path: "\(mode.rawValue)/\(name).txt"))
    }

    /// Everything the recorder sent, one entry per line.
    static func sent(_ mode: Mode, _ name: String) throws -> [String] {
        let text = try String(contentsOf: transcripts.appending(path: "\(mode.rawValue)/\(name).sent.txt"),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
