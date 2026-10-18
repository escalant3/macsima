// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing

@Test func transcriptFixturesExist() throws {
    let dir = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/transcripts")
    for mode in ["raw", "glue"] {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.appending(path: mode).path)
        #expect(files.contains { $0.hasSuffix(".txt") }, "no transcripts in \(mode)/")
    }
}
