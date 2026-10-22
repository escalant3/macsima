// SPDX-License-Identifier: GPL-2.0-or-later
//
// Cases from wxMaxima's test/unit_tests/test_TextFormat.cpp (commit 13e4aee),
// Copyright (C) 2026 Gunter Königsmann, GPL-2.0-or-later.

import Foundation
import Testing
@testable import WorksheetKit

struct TextFormatsTests {
    /// "0011" → two plain, two bold characters (digits are the raw values).
    func F(_ digits: String) -> TextFormats { digits.map { TextFormat(rawValue: UInt8(String($0))!) } }

    @Test func savedAsLineAttributes() {
        var formats = TextFormats(repeating: [], count: 12)
        for i in 0..<4 { formats[i] = .bold }
        for i in 6..<12 { formats[i] = .italic }
        #expect(TextFormatting.attributes(formats).map { "\($0.0)=\($0.1)" } == ["bold=0-4", "italic=6-12"])
        let read = TextFormatting.read(line: "bold, italic", attributes: ["bold": "0-4", "italic": "6-12"])
        #expect(read.formats == formats && read.unknown.isEmpty)
        #expect(TextFormatting.attributes(F("000")).isEmpty)
        #expect(TextFormatting.attributes(F("131")).map { "\($0.0)=\($0.1)" } == ["bold=0-3", "italic=1-2"])
        let script: TextFormats = [[], .raised, [], [], [], .lowered]
        #expect(TextFormatting.attributes(script).map { "\($0.0)=\($0.1)" } == ["superscript=1-2", "subscript=5-6"])
    }

    @Test func unknownAttributesAreKept() {
        let read = TextFormatting.read(line: "abc", attributes: ["bold": "1:2", "color": "red"])
        #expect(read.formats.isEmpty && read.unknown == ["bold": "1:2", "color": "red"])
    }

    /// Ranges count code points, so an emoji is one character.
    @Test func codePoints() {
        let read = TextFormatting.read(line: "a😀b", attributes: ["bold": "1-2"])
        #expect(read.formats == F("010"))
    }

    /// A text cell with formats survives a .wxmx round trip; lines after the
    /// first count their ranges from their own start.
    @Test func wxmxRoundTrip() throws {
        let cell = Cell(kind: .text, input: "plain bold\nmore", textFormats: F("000000111100000"))
        let back = try WXMXReader.read(try WXMXWriter.write(Worksheet(cells: [cell]))).worksheet.cells[0]
        #expect(back.input == cell.input && back.textFormats == cell.textFormats && back.preservedEditor == nil)
        let xml = WXMXWriter.contentXML(Worksheet(cells: [cell]))
        #expect(xml.contains(#"<line bold="6-10">plain bold&#x0A;more</line>"#))
    }
}
