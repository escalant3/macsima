// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

enum Phase1Exit {
    static let script = Fixtures.root.appending(path: "scripts/phase1-exit.mxs")
    /// The command-line tool, when `swift build` has produced it.
    static let tool = Fixtures.root.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/debug/maxima-session").path
    static var toolAvailable: Bool {
        Integration.maximaAvailable && FileManager.default.isExecutableFile(atPath: tool)
    }

    /// For information only: other Maxima, SBCL or gnuplot processes (wxMaxima may be running).
    static func globalProcesses() -> String {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/pgrep")
        p.arguments = ["-l", "-f", "maxima|sbcl|gnuplot"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct Phase1ExitTests {
    @Test func fiftyCommandScript() async throws {
        let script = try String(contentsOf: Phase1Exit.script, encoding: .utf8)
        let session = MaximaSession()
        try await session.start()
        let log = Collector<String>()
        let runner = ScriptRunner(session: session) { line in Task { await log.append(line) } }
        let report = await runner.run(script)
        await session.shutdown()

        #expect(report.failures.isEmpty, "\(report.failures)")
        #expect(report.statements >= 50)
        #expect(report.answers == 2)
        #expect(report.processGroups.count == 2, "one kill and restart")
        #expect(report.plotFiles.count == 2)

        // Nothing left behind.
        for group in report.processGroups {
            #expect(!Integration.groupAlive(group), "process group \(group) is gone")
        }
        for dir in report.tempDirectories {
            #expect(!FileManager.default.fileExists(atPath: dir), "\(dir) is removed")
        }
        for file in report.plotFiles {
            #expect(!FileManager.default.fileExists(atPath: file), "\(file) is removed")
        }
        #expect(Integration.maxoutFiles(for: report.processGroups).isEmpty)
        // Other suites may have their own Maxima registered at the same time.
        #expect(Set(OrphanGuard.registered).isDisjoint(with: report.processGroups))
        print("other maxima/sbcl/gnuplot processes after the run (informational):\n\(Phase1Exit.globalProcesses())")
    }

    /// SIGTERM to the host must not orphan a busy Maxima.
    @Test(.enabled(if: Phase1Exit.toolAvailable))
    func sigtermToTheHostKillsMaxima() async throws {
        let script = try Integration.script("")   // only for its folder
        let scriptFile = URL(filePath: script).deletingLastPathComponent().appending(path: "busy.mxs")
        try "!async integrate(x^30*exp(-x^2)*sin(x)^20, x);\n!sleep 60\n".write(to: scriptFile, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(filePath: Phase1Exit.tool)
        p.arguments = [scriptFile.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()

        // Read until the tool reports Maxima's process group and the computation started.
        var output = ""
        var group: pid_t?
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline, !output.contains("(running in the background)") {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            output += String(decoding: chunk, as: UTF8.self)
        }
        if let r = output.range(of: #"process group (\d+)"#, options: .regularExpression) {
            group = pid_t(output[r].split(separator: " ").last ?? "")
        }
        let g = try #require(group, "tool output: \(output)")
        #expect(Integration.groupAlive(g))

        kill(p.processIdentifier, SIGTERM)
        p.waitUntilExit()
        #expect(p.terminationReason == .uncaughtSignal && p.terminationStatus == SIGTERM)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!Integration.groupAlive(g), "the orphan guard killed Maxima")
        // The guard cannot clean files from a signal handler; the next start sweeps the folder.
        try? FileManager.default.removeItem(at: scriptFile.deletingLastPathComponent())
    }
}
