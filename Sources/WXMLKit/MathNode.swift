// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// One node of the math XML that wxMathML.lisp prints.
public enum MathNode: Equatable, Sendable {
    case element(name: String, attributes: [String: String], children: [MathNode])
    case text(String)

    public var name: String? {
        if case .element(let name, _, _) = self { name } else { nil }
    }

    public var attributes: [String: String] {
        if case .element(_, let attributes, _) = self { attributes } else { [:] }
    }

    public var children: [MathNode] {
        if case .element(_, _, let children) = self { children } else { [] }
    }

    /// Child elements, without whitespace-only text between them.
    public var elementChildren: [MathNode] {
        children.filter { $0.name != nil }
    }

    /// All text below this node, in order.
    public var textContent: String {
        switch self {
        case .text(let s): s
        case .element(_, _, let children): children.map(\.textContent).joined()
        }
    }

    public func attribute(_ key: String) -> String? { attributes[key] }
}

/// Parses math XML (a whole `<math>…</math>` or `<mth>…</mth>` chunk, or any
/// fragment) into a tree. Returns nil when the XML is not well formed.
public enum MathXMLParser {
    /// Deeper nesting is refused (the tree code is recursive; see MathMLTranslator.maxDepth).
    public static let maxDepth = 512

    public static func parse(_ xml: String) -> MathNode? {
        // A fragment may have several top-level nodes; wrap it so XMLParser sees one root.
        let delegate = TreeBuilder()
        let parser = XMLParser(data: Data("<wxml-root>\(xml)</wxml-root>".utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse(), !delegate.tooDeep, let root = delegate.root else { return nil }
        let top = root.children
        if top.count == 1, top[0].name != nil { return top[0] }
        return .element(name: "mrow", attributes: [:], children: top)
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [(name: String, attributes: [String: String], children: [MathNode])] = []
    var root: MathNode?
    var tooDeep = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard stack.count < MathXMLParser.maxDepth else {
            tooDeep = true
            parser.abortParsing()
            return
        }
        stack.append((name, attributes, []))
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let top = stack.popLast() else { return }
        let node = MathNode.element(name: top.name, attributes: top.attributes, children: top.children)
        if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        // Merge adjacent text (XMLParser splits around entities).
        if case .text(let previous)? = stack[stack.count - 1].children.last {
            stack[stack.count - 1].children[stack[stack.count - 1].children.count - 1] = .text(previous + string)
        } else {
            stack[stack.count - 1].children.append(.text(string))
        }
    }
}
