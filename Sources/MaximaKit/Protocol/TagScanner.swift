// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// One unit of Maxima output, as split by `TagScanner`.
public enum ScannerEvent: Equatable, Sendable {
    /// The content between `<PROMPT>` and `</PROMPT>`.
    case prompt(String)
    /// A whole `<math>…</math>` (or `<mth>…</mth>`) element, raw and unparsed.
    case math(String)
    /// One line of output outside any tag, without its newline. Text that
    /// runs straight into a tag is emitted on its own when the tag starts.
    case text(String)
    /// Any other top-level tag, with its raw content.
    case tag(name: String, content: String)
}

/// Splits the byte stream from Maxima's control socket into events.
///
/// The glue Lisp prints its top-level tags without attributes, so a tag starts
/// only at an exact `<name>` for one of the known names; tags inside `math`
/// carry attributes and are never matched here. The content of a tag runs to
/// the first `</name>`. Everything else is plain text, reported line by line.
///
/// The scanner works on bytes, so a UTF-8 character split across reads is
/// safe, and its events do not depend on how the input was chunked: a
/// partial line or a possible tag start at the end of the input is held
/// until more data or `flush()`. Carriage returns are dropped.
public struct TagScanner: Sendable {
    public static let promptTag = "PROMPT"
    public static let mathTags: Set<String> = ["math", "mth"]
    public static let genericTags: Set<String> = [
        "variables", "wxxml-symbols", "suppressOutput", "statusbar", "wxxml-key",
        "wxxml-asciimath", "wxasync", "watch_variables_add", "html-manual-keywords",
        "worksheetexport", "macsima-help",
    ]

    private static let openTags: [(name: String, bytes: [UInt8])] =
        ([promptTag] + mathTags.sorted() + genericTags.sorted()).map { ($0, Array("<\($0)>".utf8)) }

    private var buffer: [UInt8] = []
    /// Start of unconsumed bytes in `buffer` (compacted lazily).
    private var start = 0
    /// Where scanning resumes; everything in `start..<scan` is plain text
    /// with no newline and no tag start.
    private var scan = 0
    /// The tag being read, if any, and where its content starts.
    private var open: (name: String, close: [UInt8], contentStart: Int)?
    /// True right after a tag closed, so the newline that usually follows
    /// does not show up as an empty text line.
    private var afterTag = false

    public init() {}

    /// Adds bytes and returns the events they complete.
    public mutating func feed(_ data: some Sequence<UInt8>) -> [ScannerEvent] {
        for byte in data where byte != 0x0D { buffer.append(byte) }
        var events: [ScannerEvent] = []
        process(into: &events)
        compact()
        return events
    }

    /// Emits whatever is held back: a partial line, or an unfinished tag as text.
    public mutating func flush() -> [ScannerEvent] {
        var events: [ScannerEvent] = []
        process(into: &events)
        open = nil   // `start` is still at the "<" of an unfinished tag
        if start < buffer.count {
            events.append(.text(Self.string(buffer[start..<buffer.count])))
        }
        buffer.removeAll(keepingCapacity: true)
        start = 0
        scan = 0
        afterTag = false
        return events
    }

    private mutating func process(into events: inout [ScannerEvent]) {
        while true {
            if let tag = open {
                guard let end = Self.find(tag.close, in: buffer, from: max(scan, tag.contentStart)) else {
                    // Resume just before the end, in case the close tag is split.
                    scan = max(tag.contentStart, buffer.count - tag.close.count + 1)
                    return
                }
                let content = Self.string(buffer[tag.contentStart..<end])
                switch tag.name {
                case Self.promptTag: events.append(.prompt(content))
                case _ where Self.mathTags.contains(tag.name):
                    events.append(.math("<\(tag.name)>\(content)</\(tag.name)>"))
                default: events.append(.tag(name: tag.name, content: content))
                }
                open = nil
                start = end + tag.close.count
                scan = start
                afterTag = true
                continue
            }
            guard let i = buffer[scan...].firstIndex(where: { $0 == 0x0A || $0 == 0x3C }) else {
                scan = buffer.count
                return
            }
            if buffer[i] == 0x0A {
                if !(afterTag && i == start) {
                    events.append(.text(Self.string(buffer[start..<i])))
                }
                afterTag = false
                start = i + 1
                scan = start
                continue
            }
            switch matchOpenTag(at: i) {
            case .need:
                scan = i
                return
            case .no:
                scan = i + 1
            case .tag(let name, let length):
                if i > start {
                    events.append(.text(Self.string(buffer[start..<i])))
                }
                afterTag = false
                open = (name, Array("</\(name)>".utf8), i + length)
                start = i
                scan = i + length
            }
        }
    }

    private enum Match { case no, need, tag(String, Int) }

    private func matchOpenTag(at i: Int) -> Match {
        let available = buffer.count - i
        var maybe = false
        for (name, bytes) in Self.openTags {
            let n = min(bytes.count, available)
            if buffer[i..<(i + n)].elementsEqual(bytes[0..<n]) {
                if n == bytes.count { return .tag(name, n) }
                maybe = true
            }
        }
        return maybe ? .need : .no
    }

    private mutating func compact() {
        guard start > 4096, start * 2 > buffer.count else { return }
        buffer.removeFirst(start)
        scan -= start
        if let tag = open { open = (tag.name, tag.close, tag.contentStart - start) }
        start = 0
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        guard let first = needle.first, haystack.count - from >= needle.count else { return nil }
        var i = from
        let last = haystack.count - needle.count
        while i <= last {
            guard let j = haystack[i...last].firstIndex(of: first) else { return nil }
            if haystack[j..<(j + needle.count)].elementsEqual(needle) { return j }
            i = j + 1
        }
        return nil
    }

    private static func string(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}
