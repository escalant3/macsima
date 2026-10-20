// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// One entry of the completion list: a name, or a function template with
/// `<argument>` placeholders (`integrate(<expr>, <x>)`).
public struct CompletionItem: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// Maxima's own names and wxMaxima's template list.
        case maxima
        /// Defined or used in this worksheet's code cells.
        case worksheet
    }

    public var name: String
    public var template: String?
    public var source: Source

    public init(name: String, template: String? = nil, source: Source) {
        self.name = name
        self.template = template
        self.source = source
    }

    /// What accepting the item inserts.
    public var insertion: String { template ?? name }
}

/// The names and templates completion draws from.
public struct CompletionIndex: Sendable {
    public var names: Set<String> = []
    /// Templates by function name; a name can have several (`diff` has five).
    public var templates: [String: [String]] = [:]

    public init(names: Set<String> = [], templates: [String: [String]] = [:]) {
        self.names = names
        self.templates = templates
    }

    public mutating func add(name: String, template: String? = nil) {
        names.insert(name)
        if let template, !(templates[name]?.contains(template) ?? false) { templates[name, default: []].append(template) }
    }

    public mutating func merge(_ other: CompletionIndex) {
        names.formUnion(other.names)
        for (name, list) in other.templates {
            for template in list { add(name: name, template: template) }
        }
    }

    /// wxMaxima's built-in list (`Resources/builtin_commands.txt`): a line
    /// with `(` is a template, any other line a name.
    public static let builtin: CompletionIndex = {
        guard let url = Bundle.module.url(forResource: "builtin_commands", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return CompletionIndex() }
        return parseList(text)
    }()

    public static func parseList(_ text: String) -> CompletionIndex {
        var index = CompletionIndex()
        for line in text.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let paren = line.firstIndex(of: "(") {
                index.add(name: String(line[..<paren]), template: line)
            } else {
                index.add(name: line)
            }
        }
        return index
    }
}

/// Autocompletion, after wxMaxima's (`Autocomplete.cpp`,
/// `Worksheet::Autocomplete`, `EditorCell::FindNextTemplate`, Version-26.09.0):
/// names from Maxima and the built-in list, words from the worksheet's code
/// cells, templates whose `<placeholders>` Tab steps through.
/// Offsets are UTF-16, as the text views count.
public enum MaximaCompletion {
    /// The name the caret is in or right after: its whole range, and the
    /// part before the caret, which is what gets completed. Nil in strings,
    /// comments and anywhere else no name is being typed.
    public static func word(in text: String, caret: Int) -> (range: NSRange, prefix: String)? {
        guard let token = MaximaTokenizer.tokenize(text).first(where: {
            $0.kind == .identifier && $0.range.lowerBound < caret && caret <= $0.range.upperBound
        }) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: token.range.lowerBound, length: token.range.count)
        return (range, ns.substring(with: NSRange(location: range.location, length: caret - range.location)))
    }

    /// The names a code cell uses, and the functions it defines, as templates:
    /// `f(x, [l]) := ...` and `define(f(x), ...)` give `f(<x>, <[l]>)`.
    /// The way Maxima prints its own (`$print_function` in wxMathML.lisp).
    public static func symbols(in text: String, skipping skipped: NSRange? = nil) -> CompletionIndex {
        let tokens = MaximaTokenizer.tokenize(text)
        let ns = text as NSString
        func piece(_ t: MaximaToken) -> String { ns.substring(with: NSRange(location: t.range.lowerBound, length: t.range.count)) }
        var index = CompletionIndex()
        for (k, token) in tokens.enumerated() where token.kind == .identifier {
            // The word being completed is no completion of itself.
            if let skipped, token.range.lowerBound == skipped.location, token.range.count == skipped.length { continue }
            let name = piece(token)
            index.names.insert(name)
            guard k + 1 < tokens.count, piece(tokens[k + 1]) == "(",
                  let close = matchingClose(tokens, from: k + 1, piece) else { continue }
            let defined: Bool
            if close + 1 < tokens.count, tokens[close + 1].kind == .operator {
                let op = piece(tokens[close + 1])
                defined = op.hasPrefix(":=") || op.hasPrefix("::=")
            } else {
                defined = false
            }
            let inDefine = k >= 2 && piece(tokens[k - 1]) == "(" && piece(tokens[k - 2]) == "define"
            guard defined || inDefine,
                  let args = arguments(tokens, from: k + 2, to: close, piece) else { continue }
            index.add(name: name, template: "\(name)(\(args.map { "<\($0)>" }.joined(separator: ", ")))")
        }
        return index
    }

    /// The index of the bracket closing the one at `open`.
    private static func matchingClose(_ tokens: [MaximaToken], from open: Int, _ piece: (MaximaToken) -> String) -> Int? {
        var depth = 0
        for k in open..<tokens.count where tokens[k].kind == .bracket {
            depth += "([{".contains(piece(tokens[k])) ? 1 : -1
            if depth == 0 { return k }
        }
        return nil
    }

    /// A definition's parameters: names, or `[name]` for a rest parameter.
    /// Nil when one is something else (a pattern, a default).
    private static func arguments(_ tokens: [MaximaToken], from start: Int, to end: Int,
                                  _ piece: (MaximaToken) -> String) -> [String]? {
        var args: [String] = [], current: [MaximaToken] = []
        for k in start...end {
            if k == end || tokens[k].kind == .separator {
                let text = current.map(piece)
                switch current.map(\.kind) {
                case [] where k == end && args.isEmpty: return []
                case [.identifier]: args.append(text[0])
                case [.bracket, .identifier, .bracket] where text[0] == "[" && text[2] == "]": args.append(text.joined())
                default: return nil
                }
                current = []
            } else if tokens[k].kind != .comment {
                current.append(tokens[k])
            }
        }
        return args
    }

    /// The entries that complete `prefix`: names that start with it, and the
    /// templates of those names. Exact matches come first, then the rest
    /// alphabetically; names in the worksheet that Maxima doesn't know are
    /// marked as the worksheet's. When nothing matches with the case as typed
    /// (Maxima's names are case-sensitive), the case is ignored.
    public static func completions(of prefix: String, maxima: CompletionIndex, worksheet: CompletionIndex,
                                   templatesOnly: Bool = false) -> [CompletionItem] {
        guard !prefix.isEmpty else { return [] }
        for caseSensitive in [true, false] {
            let lowered = prefix.lowercased()
            func matches(_ name: String) -> Bool {
                caseSensitive ? name.hasPrefix(prefix) : name.lowercased().hasPrefix(lowered)
            }
            let names = maxima.names.union(worksheet.names).filter(matches)
            var items: [CompletionItem] = []
            for name in names {
                let source: CompletionItem.Source = maxima.names.contains(name) ? .maxima : .worksheet
                let theirs = worksheet.templates[name] ?? [], ours = maxima.templates[name] ?? []
                // The worksheet's own definition replaces Maxima's.
                let templates = theirs.isEmpty ? ours : theirs
                if templates.isEmpty {
                    if !templatesOnly { items.append(CompletionItem(name: name, source: source)) }
                } else {
                    let from: CompletionItem.Source = theirs.isEmpty ? .maxima : .worksheet
                    items += templates.map { CompletionItem(name: name, template: $0, source: from) }
                }
            }
            // Show Template: the templates of the name typed, as wxMaxima's
            // "perfect completions", else those of the names it starts.
            if templatesOnly, items.contains(where: { $0.name == prefix }) { items = items.filter { $0.name == prefix } }
            items.sort { a, b in
                let ea = a.name == prefix, eb = b.name == prefix
                if ea != eb { return ea }
                if a.name != b.name { return a.name < b.name }
                return (a.template ?? "").count < (b.template ?? "").count
            }
            if !items.isEmpty { return items }
        }
        return []
    }

    // MARK: - Placeholders

    /// The `<argument>` placeholders in `text`, outside strings and comments.
    /// wxMaxima's pattern, `<[^> \n]+>`, but not right after a name, number or
    /// closing bracket, where `<` is a comparison (`a<b>c`).
    public static func placeholders(in text: String) -> [NSRange] {
        let ns = text as NSString
        let quiet = MaximaTokenizer.tokenize(text).filter { $0.kind == .string || $0.kind == .comment }.map(\.range)
        var found: [NSRange] = []
        for match in text.matches(of: /<[^> \n]+>/) {
            let range = NSRange(match.range, in: text)
            if quiet.contains(where: { $0.contains(range.location) }) { continue }
            if range.location > 0, let before = Unicode.Scalar(ns.character(at: range.location - 1)),
               CharacterSet.alphanumerics.contains(before) || "_%)]}".unicodeScalars.contains(before) { continue }
            found.append(range)
        }
        return found
    }

    /// The placeholder Tab (or Shift+Tab, `backwards`) goes to from
    /// `selection`: the next one after it, wrapping round the cell. With
    /// the only one selected, it stays selected (Tab doesn't type over it).
    public static func nextPlaceholder(in text: String, after selection: NSRange, backwards: Bool = false) -> NSRange? {
        let found = placeholders(in: text)
        let all = found.filter { $0 != selection }
        let next = backwards
            ? all.last(where: { NSMaxRange($0) <= selection.location }) ?? all.last
            : all.first(where: { $0.location >= NSMaxRange(selection) }) ?? all.first
        return next ?? (found.contains(selection) ? selection : nil)
    }
}
