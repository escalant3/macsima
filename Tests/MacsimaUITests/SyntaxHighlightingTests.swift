// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import Foundation
import Testing
@testable import MacsimaUI

@MainActor
struct SyntaxHighlightingTests {
    static let transcript = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/transcripts/glue/01-integrate.txt")

    /// The symbols tag of a real session start.
    @Test func symbolsFromASession() throws {
        let received = try String(contentsOf: Self.transcript, encoding: .utf8)
        let tag = try #require(received.firstMatch(of: /<wxxml-symbols>(.*?)<\/wxxml-symbols>/.dotMatchesNewlines()))
        let symbols = MaximaSymbols()
        symbols.ingest(String(tag.1))
        #expect(symbols.names.count > 2000)
        for name in ["integrate", "sin", "expand", "%pi", "ratprint"] { #expect(symbols.names.contains(name), "\(name)") }
        // Single letters Maxima's code interned stay plain.
        for name in ["x", "y", "a", "t"] { #expect(!symbols.names.contains(name), "\(name)") }
    }

    @Test func templates() {
        let symbols = MaximaSymbols()
        symbols.ingest("<function>myf</function><template>myf(&lt;x&gt;, &lt;y&gt;)</template>")
        #expect(symbols.templates["myf"] == "myf(<x>, <y>)")
        #expect(symbols.names.contains("myf"))
    }

    @Test func colours() {
        let builtins: Set<String> = ["sin"]
        #expect(SyntaxHighlighter.color(for: .identifier, text: "sin", builtins: builtins) == .systemTeal)
        #expect(SyntaxHighlighter.color(for: .identifier, text: "foo", builtins: builtins) == nil)
        #expect(SyntaxHighlighter.color(for: .comment, text: "/* */", builtins: builtins) == .systemGray)
    }
}
