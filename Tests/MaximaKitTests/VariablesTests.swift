// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

/// Replies of `macsima-values` and `macsima-variable-names` (macsima.lisp)
/// as Maxima 5.50.0 sent them, recorded with MACSIMA_RECORD_VARIABLES=1.
enum VariablesFixtures {
    static let dir = Fixtures.transcripts.appending(path: "variables")
    static let setup = "x: 3$ big: makelist(i, i, 1, 2000)$ s: \"a<b & c\"$ f(t) := t^2$ m: matrix([1,2],[3,4])$ X: 1$"
    static let names = ["x", "big", "s", "f", "m", "X", "nothing", "%pi"]

    static func text(_ name: String) throws -> String {
        try String(contentsOf: dir.appending(path: name), encoding: .utf8)
    }
}

struct VariablesTests {
    @Test func parsesValues() throws {
        let values = MaximaVariables.parse(try VariablesFixtures.text("values.txt"))
        #expect(values.map(\.name) == VariablesFixtures.names)
        #expect(values[0] == WatchedValue(name: "x", kind: .value, text: "3"))
        #expect(values[1].isCut && values[1].text.count == 4000 && values[1].text.hasPrefix("[1,2,3,"))
        #expect(values[2].text == "a<b & c", "escapes undone")
        #expect(values[3] == WatchedValue(name: "f", kind: .function, text: "f(t):=t^2"))
        #expect(values[4].text == "matrix([1,2],[3,4])")
        #expect(values[5].text == "1", "case matters: X is not x")
        #expect(values[6].kind == .unbound)
        #expect(values[7].kind == .unbound, "%pi is a constant, with no value of its own")
    }

    @Test func parsesNames() throws {
        let names = MaximaVariables.parseNames(try VariablesFixtures.text("names.txt"))
        // The user's maxima-init.mac may set some first (draw_command, here).
        #expect(names.suffix(5) == ["x", "big", "s", "m", "X"])
        #expect(!names.contains("f"), "functions are not in values")
    }
}

@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct VariablesIntegrationTests {
    private func reply(_ tag: String, _ events: inout AsyncStream<SessionEvent>.Iterator) async -> String? {
        while let e = await events.next() {
            if case .tag(tag, let content) = e { return content }
        }
        return nil
    }

    @Test func valuesFromARealMaxima() async throws {
        let session = MaximaSession()
        var events = session.events.makeAsyncIterator()
        try await session.start()
        _ = await drain(try await session.evaluate(cellID: "a", text: VariablesFixtures.setup))
        await session.values(of: VariablesFixtures.names)
        let values = try #require(await reply("macsima-values", &events))
        await session.variableNames()
        let names = try #require(await reply("macsima-variable-names", &events))
        if ProcessInfo.processInfo.environment["MACSIMA_RECORD_VARIABLES"] == "1" {
            try FileManager.default.createDirectory(at: VariablesFixtures.dir, withIntermediateDirectories: true)
            try values.write(to: VariablesFixtures.dir.appending(path: "values.txt"), atomically: true, encoding: .utf8)
            try names.write(to: VariablesFixtures.dir.appending(path: "names.txt"), atomically: true, encoding: .utf8)
        }
        #expect(values == (try VariablesFixtures.text("values.txt")))
        #expect(MaximaVariables.parseNames(names).suffix(5) == ["x", "big", "s", "m", "X"])
        await session.shutdown()
    }
}
