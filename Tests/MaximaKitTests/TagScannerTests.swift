// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import MaximaKit

/// Deterministic generator so a failing chunking can be reproduced from its seed.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func scanWhole(_ data: Data) -> [ScannerEvent] {
    var scanner = TagScanner()
    return scanner.feed(data) + scanner.flush()
}

func scanChunked(_ data: Data, sizes: () -> Int) -> [ScannerEvent] {
    var scanner = TagScanner()
    var events: [ScannerEvent] = []
    let bytes = [UInt8](data)
    var i = 0
    while i < bytes.count {
        let n = min(max(1, sizes()), bytes.count - i)
        events += scanner.feed(bytes[i..<(i + n)])
        i += n
    }
    return events + scanner.flush()
}

struct TagScannerTests {
    static let allFixtures: [(Fixtures.Mode, String)] =
        Fixtures.Mode.allCases.flatMap { mode in Fixtures.names(mode).map { (mode, $0) } }

    @Test func fixturesAreThere() {
        #expect(Self.allFixtures.count >= 49)
    }

    @Test(arguments: allFixtures.map { "\($0.0.rawValue)/\($0.1)" })
    func chunkingDoesNotChangeEvents(_ fixture: String) throws {
        let parts = fixture.split(separator: "/").map(String.init)
        let data = try Fixtures.received(Fixtures.Mode(rawValue: parts[0])!, parts[1])
        let whole = scanWhole(data)
        #expect(scanChunked(data, sizes: { 1 }) == whole, "1-byte chunks")
        for seed in [1, 2, 3, 42] as [UInt64] {
            var rng = SplitMix64(state: seed)
            let small = scanChunked(data, sizes: { Int.random(in: 1...16, using: &rng) })
            #expect(small == whole, "seed \(seed), 1...16")
            let large = scanChunked(data, sizes: { Int.random(in: 1...70_000, using: &rng) })
            #expect(large == whole, "seed \(seed), 1...70000")
        }
    }

    @Test func glueIntegrateEvents() throws {
        let events = scanWhole(try Fixtures.received(.glue, "01-integrate"))
        guard case .text(let first) = events.first else { Issue.record("no text first"); return }
        #expect(first.hasPrefix("pid="))
        #expect(events.contains(.text("(%i1) ")), "the raw prompt before the glue is plain text")
        let names = events.compactMap { if case .tag(let n, _) = $0 { n } else { nil } }
        #expect(names == ["suppressOutput", "wxxml-symbols", "variables", "variables"])
        let suppress = events.compactMap { if case .tag("suppressOutput", let c) = $0 { c } else { nil } }
        #expect(suppress.first?.contains("<wxxml-key>\(Fixtures.token)</wxxml-key>") == true)
        // The first result has no wrapped prompt before it: (%i1) came before the glue.
        #expect(Array(events.suffix(2)) == [
            .math(#"<math><lbl altCopy="%o1">(%o1) </lbl><mo>-</mo><fn lisp="wxxml-function"><fnm lisp="wxxml-function">cos</fnm><mrow><p><mrow><mi lisp="*var-tag*">x</mi></mrow></p></mrow></fn></math>"#),
            .prompt("(%i2) "),
        ])
    }

    @Test func errorTextIsLines() throws {
        let events = scanWhole(try Fixtures.received(.glue, "04-error-division"))
        let texts = events.compactMap { if case .text(let t) = $0 { t } else { nil } }
        #expect(texts.suffix(2) == [
            "expt: undefined: 0 to a negative exponent.",
            " -- an error. To debug this try: debugmode(true);",
        ])
    }

    @Test func questionPromptKeepsMath() throws {
        let events = scanWhole(try Fixtures.received(.glue, "08-asksign"))
        #expect(events.contains(.prompt(
            #"<math><st>Is </st><mi lisp="*var-tag*">y</mi><st> positive, negative or zero?</st></math>"#)))
    }

    @Test func splitUTF8() {
        let bytes = Array("x\u{3B1}y\n<math>\u{3B2}</math>\n".utf8)
        for cut in 1..<bytes.count {
            var s = TagScanner()
            let events = s.feed(bytes[..<cut]) + s.feed(bytes[cut...]) + s.flush()
            #expect(events == [.text("x\u{3B1}y"), .math("<math>\u{3B2}</math>")], "cut at \(cut)")
        }
    }

    @Test func carriageReturnsAndUnknownTags() {
        var s = TagScanner()
        let events = s.feed(Data("a\r\n<foo>b</foo>\n<mi lisp=\"x\">c</mi>\n".utf8)) + s.flush()
        #expect(events == [.text("a"), .text("<foo>b</foo>"), .text("<mi lisp=\"x\">c</mi>")])
    }

    @Test func heldBackUntilComplete() {
        var s = TagScanner()
        #expect(s.feed(Data("(%i1) <PRO".utf8)).isEmpty)
        #expect(s.feed(Data("MPT>(%i2) </PROM".utf8)) == [.text("(%i1) ")])
        #expect(s.feed(Data("PT>tail".utf8)) == [.prompt("(%i2) ")])
        #expect(s.flush() == [.text("tail")])
    }

    @Test func blankLinesInTextAreKept() {
        var s = TagScanner()
        let events = s.feed(Data("<math>m</math>\nerr:\n\n x\n".utf8))
        #expect(events == [.math("<math>m</math>"), .text("err:"), .text(""), .text(" x")])
    }

    @Test func unfinishedTagFlushesAsText() {
        var s = TagScanner()
        #expect(s.feed(Data("<variables>abc".utf8)).isEmpty)
        #expect(s.flush() == [.text("<variables>abc")])
    }

    @Test func startupTiming() throws {
        let data = try Fixtures.received(.glue, "01-integrate")
        let clock = ContinuousClock()
        var events: [ScannerEvent] = []
        let whole = clock.measure { events = scanWhole(data) }
        let byByte = clock.measure { _ = scanChunked(data, sizes: { 1 }) }
        print("TagScanner: \(data.count) bytes whole in \(whole), byte by byte in \(byByte), \(events.count) events")
        #expect(whole < .seconds(1))
        #expect(byByte < .seconds(5))
    }
}
