// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// A watched variable's state, from `macsima-values` (macsima.lisp).
public struct WatchedValue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `x: 3`.
        case value
        /// No value, a function definition (`f(x) := ...`).
        case function
        /// Neither.
        case unbound
        /// Maxima could not print it.
        case error
    }

    public var name: String
    public var kind: Kind
    /// The value in linear form, the definition, or the error.
    public var text: String
    /// The value was longer than Maxima sends (4000 characters).
    public var isCut: Bool

    public init(name: String, kind: Kind, text: String = "", isCut: Bool = false) {
        self.name = name
        self.kind = kind
        self.text = text
        self.isCut = isCut
    }
}

public enum MaximaVariables {
    /// The content of a `<macsima-values>` tag.
    public static func parse(_ content: String) -> [WatchedValue] {
        content.matches(of: /<variable>(.*?)<\/variable>/.dotMatchesNewlines()).map { match in
            let body = String(match.1)
            let name = field("name", body) ?? ""
            if body.contains("<unbound/>") { return WatchedValue(name: name, kind: .unbound) }
            if let error = field("error", body) { return WatchedValue(name: name, kind: .error, text: error) }
            return WatchedValue(name: name, kind: field("kind", body) == "function" ? .function : .value,
                                text: field("value", body) ?? "", isCut: body.contains("<cut/>"))
        }
    }

    /// The content of a `<macsima-variable-names>` tag.
    public static func parseNames(_ content: String) -> [String] {
        content.matches(of: /<name>(.*?)<\/name>/).map { MaximaHelp.unescape(String($0.1)) }
    }

    private static func field(_ tag: String, _ body: String) -> String? {
        guard let a = body.range(of: "<\(tag)>"), let b = body.range(of: "</\(tag)>", range: a.upperBound..<body.endIndex) else { return nil }
        return MaximaHelp.unescape(String(body[a.upperBound..<b.lowerBound]))
    }
}
