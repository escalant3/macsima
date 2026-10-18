// SPDX-License-Identifier: GPL-2.0-or-later

import Darwin
import Foundation

/// A private temp folder per Maxima process, used as its `TMPDIR` and
/// `maxima_tempdir`. Plot files (`maxout_*`) and gnuplot scripts land here,
/// so cleaning up after a kill cannot touch another Maxima's files (wxMaxima
/// deletes every `maxout*` in the shared temp folder instead).
struct SessionTempDirectory: Sendable {
    static let prefix = "macsima-"
    let path: String

    /// Creates `macsima-<host pid>-XXXXXX` in the system temp folder.
    static func create() throws(MaximaError) -> SessionTempDirectory {
        sweepStale()
        var template = Array((systemTemp + "/\(prefix)\(getpid())-XXXXXX").utf8CString)
        guard let made = mkdtemp(&template) else {
            throw .spawnFailed("cannot create a temp folder: \(String(cString: strerror(errno)))")
        }
        return SessionTempDirectory(path: String(cString: made))
    }

    /// The host's temp folder without a trailing slash.
    static var systemTemp: String {
        var t = NSTemporaryDirectory()
        while t.count > 1 && t.hasSuffix("/") { t.removeLast() }
        return t
    }

    var logPath: String { path + "/maxima.log" }

    /// The last lines of Maxima's own stdout and stderr.
    func logTail(lines: Int = 20) -> String {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    /// Deletes the folder and everything in it, plus any `maxout_<lispPID>_*`
    /// file Maxima may still have written to the system temp folder.
    func remove(lispPIDs: [pid_t]) {
        try? FileManager.default.removeItem(atPath: path)
        for pid in lispPIDs { Self.removeMaxout(in: Self.systemTemp, lispPID: pid) }
    }

    static func removeMaxout(in folder: String, lispPID: pid_t) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        for name in names where name.hasPrefix("maxout_\(lispPID)_") || name == "maxout_\(lispPID).gnuplot" {
            try? FileManager.default.removeItem(atPath: folder + "/" + name)
        }
    }

    /// Removes folders left by hosts that are no longer running.
    static func sweepStale() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: systemTemp)) ?? []
        for name in names where name.hasPrefix(prefix) {
            let parts = name.dropFirst(prefix.count).split(separator: "-")
            guard let owner = parts.first.flatMap({ pid_t($0) }) else { continue }
            if owner != getpid() && kill(owner, 0) != 0 && errno == ESRCH {
                try? FileManager.default.removeItem(atPath: systemTemp + "/" + name)
            }
        }
    }
}
