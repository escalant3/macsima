// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MaximaKit

enum Integration {
    static let maximaPath = "/opt/homebrew/bin/maxima"
    static var maximaAvailable: Bool { FileManager.default.isExecutableFile(atPath: maximaPath) }

    static func randomToken() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// Writes an executable shell script into a fresh temp folder.
    static func script(_ body: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appending(path: "macsima-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appending(path: "fake-maxima").path
        try ("#!/bin/sh\n" + body + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
        return path
    }

    static func groupAlive(_ group: pid_t) -> Bool {
        killpg(group, 0) == 0 || errno == EPERM
    }

    /// `maxout*` files anywhere in the system temp folder whose name holds one of `pids`.
    static func maxoutFiles(for pids: [pid_t]) -> [String] {
        let tmp = NSTemporaryDirectory()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmp)) ?? []
        return names.filter { name in pids.contains { name.hasPrefix("maxout_\($0)") } }
    }
}

/// Collects values from a background stream so a test can wait for one.
actor Collector<T: Sendable> {
    private(set) var items: [T] = []
    func append(_ item: T) { items.append(item) }

    /// Polls until `predicate` holds for the collected items, or times out.
    func wait(timeout: Duration = .seconds(30), _ predicate: @Sendable ([T]) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate(items) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate(items)
    }
}
