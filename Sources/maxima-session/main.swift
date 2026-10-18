// SPDX-License-Identifier: GPL-2.0-or-later
//
// Runs a session script through MaximaSession and prints the event log.
//
// Usage: maxima-session <script.mxs> [--maxima <path>] [--quiet]
// Exits 1 when an !expect line fails, 2 when Maxima cannot start.
// The script format is described in MaximaKit's ScriptRunner.

import Foundation
import MaximaKit

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("maxima-session: \(message)\n".utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
var config = MaximaConfiguration()
if let i = args.firstIndex(of: "--maxima"), i + 1 < args.count {
    config.maximaPath = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
let quiet = args.contains("--quiet")
args.removeAll { $0 == "--quiet" }
guard args.count == 1, let script = try? String(contentsOfFile: args[0], encoding: .utf8) else {
    fail("usage: maxima-session <script.mxs> [--maxima <path>] [--quiet]", code: 2)
}

OrphanGuard.install()
setvbuf(stdout, nil, _IOLBF, 0)
let clock = ContinuousClock()
let started = clock.now
func log(_ line: String) {
    if quiet && !line.hasPrefix("!!") && !line.hasPrefix("--") { return }
    let t = (clock.now - started).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
    print("\(t.padding(toLength: 8, withPad: " ", startingAt: 0)) \(line)")
}

let session = MaximaSession(configuration: config)
let watcher = Task {
    for await event in session.events {
        switch event {
        case .slowStart: log("-- Maxima is slow to connect")
        case .died(let why): log("-- Maxima died: \(why)")
        case .async(let id, let content): log("[\(id)] async (cell finished): \(MathText.plain(content))")
        case .output(let e): log("-- output outside a cell: \(e)")
        default: break
        }
    }
}
do {
    try await session.start()
} catch {
    fail("\(error)", code: 2)
}
log("-- Maxima running, process group \(await session.processGroup.map(String.init) ?? "?"), interrupt channel \(await session.interruptChannelReady ? "up" : "down")")
let report = await ScriptRunner(session: session, log: log).run(script)
await session.shutdown()
_ = await watcher.value
log("-- \(report.statements) statements, \(report.answers) answers, \(report.cells) cells, \(report.processGroups.count) Maxima processes")
for f in report.failures { log("!! \(f)") }
log(report.failures.isEmpty ? "-- PASS" : "-- FAIL (\(report.failures.count))")
exit(report.failures.isEmpty ? 0 : 1)
