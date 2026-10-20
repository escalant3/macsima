// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

/// Replies of `macsima-help` (macsima.lisp) as Maxima 5.50.0 sent them,
/// recorded by `HelpIntegrationTests` with MACSIMA_RECORD_HELP=1.
enum HelpFixtures {
    static let dir = Fixtures.transcripts.appending(path: "help")
    static let topics = ["integrate", "diff", "nosuchtopic", ":="]

    static func file(_ topic: String) -> URL {
        dir.appending(path: topic == ":=" ? "colon-equals.txt" : "\(topic).txt")
    }

    static func page(_ topic: String) throws -> HelpPage {
        MaximaHelp.parse(try String(contentsOf: file(topic), encoding: .utf8))
    }
}

struct HelpTests {
    @Test func parsesOneEntry() throws {
        let page = try HelpFixtures.page("integrate")
        #expect(page.topic == "integrate")
        #expect(page.entries.map(\.name) == ["integrate"])
        #expect(page.entries[0].section == "Functions and Variables for Integration")
        #expect(page.entries[0].text.contains("integrate (<expr>, <x>, <a>, <b>)"), "escapes undone")
        #expect(page.related.contains("integrate_use_rootsof"))
        #expect(!page.related.contains("integrate"), "the topic itself is no related topic")
        #expect(page.error == nil)
    }

    @Test func parsesSeveralEntries() throws {
        let page = try HelpFixtures.page("diff")
        #expect(page.entries.map(\.name) == ["diff", "diff <1>", "diff <2>"])
        #expect(page.entries[2].section == "Functions and Variables for itensor")
    }

    @Test func parsesNoEntry() throws {
        let page = try HelpFixtures.page("nosuchtopic")
        #expect(page.entries.isEmpty && page.related.isEmpty && page.error == nil)
    }

    @Test func operators() throws {
        #expect(try HelpFixtures.page(":=").entries.first?.name == ":=")
    }

    @Test func references() throws {
        let text = try HelpFixtures.page("integrate").entries[0].text
        let names = MaximaHelp.references(in: text).map(\.name)
        #expect(names.contains("quad_qag") && names.contains("antid"))
    }

    @Test func blocks() throws {
        let blocks = MaximaHelp.blocks(try HelpFixtures.page("integrate").entries[0].text)
        #expect(blocks.prefix(3) == [.heading("Function: integrate"), .signature("integrate (<expr>, <x>)"),
                                     .signature("integrate (<expr>, <x>, <a>, <b>)")])
        guard case .prose(let first, 0, false) = blocks[3] else { Issue.record("\(blocks[3])"); return }
        #expect(first.hasPrefix("Attempts to symbolically compute the integral of <expr> with respect to <x>."))
        #expect(!first.contains("  with") && !first.contains("\n"), "one paragraph")
        #expect(blocks.contains(.prose("Elementary indefinite and definite integrals.", level: 1, bullet: true)))
        #expect(blocks.contains { if case .code(let c) = $0 { c.hasPrefix("(%i1) integrate (sin(x)^3, x);\n") } else { false } },
                "examples keep their lines, without the indentation")
        let all = blocks.compactMap { if case .prose(let p, _, _) = $0 { p } else { nil } }.joined()
        #expect(all.contains("see also ‘ldefint’.") && !all.contains("*note"), "info references become ‘name’")
    }

    @Test func topicAtCaret() {
        #expect(MaximaHelp.topic(in: "x: integrate(f, t)", caret: 3) == "integrate", "at the start of the name")
        #expect(MaximaHelp.topic(in: "x: integrate(f, t)", caret: 12) == "integrate", "at its end")
        #expect(MaximaHelp.topic(in: "f(x) := x", caret: 6) == ":=")
        #expect(MaximaHelp.topic(in: "for i thru 3 do", caret: 13) == "do", "keywords too")
        #expect(MaximaHelp.topic(in: "\"integrate\"", caret: 4) == nil)
        #expect(MaximaHelp.topic(in: "a   b", caret: 2) == nil)
    }
}

@Suite(.serialized, .enabled(if: Integration.maximaAvailable))
struct HelpIntegrationTests {
    /// Waits for the next `macsima-help` reply on the session's events.
    private func reply(_ events: inout AsyncStream<SessionEvent>.Iterator) async -> String? {
        while let e = await events.next() {
            if case .tag("macsima-help", let content) = e { return content }
        }
        return nil
    }

    @Test func helpFromTheManual() async throws {
        let session = MaximaSession()
        var events = session.events.makeAsyncIterator()
        try await session.start()
        for topic in HelpFixtures.topics {
            await session.help(topic)
            let content = try #require(await reply(&events))
            if ProcessInfo.processInfo.environment["MACSIMA_RECORD_HELP"] == "1" {
                try FileManager.default.createDirectory(at: HelpFixtures.dir, withIntermediateDirectories: true)
                try content.write(to: HelpFixtures.file(topic), atomically: true, encoding: .utf8)
            }
            #expect(MaximaHelp.parse(content) == (try HelpFixtures.page(topic)), "\(topic) matches its fixture")
        }
        // No input label used up: the next statement is still (%i1).
        let cell = await drain(try await session.evaluate(cellID: "a", text: "1;"))
        #expect(cell.contains(.prompt(label: 2)), "the prompt after (%i1) is (%i2)")
        await session.shutdown()
    }

    @Test func helpWaitsWhileAQuestionIsOpen() async throws {
        let session = MaximaSession()
        var events = session.events.makeAsyncIterator()
        try await session.start()
        var it = try await session.evaluate(cellID: "q", text: "asksign(y);").makeAsyncIterator()
        var asked: [CellEvent] = []
        await collect(&it, into: &asked)
        #expect(await session.state == .question)
        // Sent now, this would be read as the answer.
        await session.help("diff")
        try await session.answer("pos")
        await collect(&it, into: &asked)
        #expect(asked.contains { if case .math(let m) = $0 { m.contains("pos") } else { false } })
        #expect(asked.last == .finished(.completed))
        let page = MaximaHelp.parse(try #require(await reply(&events)))
        #expect(page.entries.count == 3)
        await session.shutdown()
    }
}
