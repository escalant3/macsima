// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// A small XML tree with one canonical serialization (attributes sorted,
/// fixed escaping), so XML the app stores comes back byte for byte after a
/// `.wxmx` round trip. Text and whitespace are kept as they are.
public indirect enum XMLNode: Equatable, Sendable {
    case element(name: String, attributes: [String: String], children: [XMLNode])
    case text(String)

    public var name: String? {
        if case .element(let name, _, _) = self { name } else { nil }
    }

    public var attributes: [String: String] {
        if case .element(_, let attributes, _) = self { attributes } else { [:] }
    }

    public var children: [XMLNode] {
        if case .element(_, _, let children) = self { children } else { [] }
    }

    public var elementChildren: [XMLNode] { children.filter { $0.name != nil } }

    public var textContent: String {
        switch self {
        case .text(let s): s
        case .element(_, _, let children): children.map(\.textContent).joined()
        }
    }

    /// The node with `attributes` replaced.
    public func with(attributes new: [String: String]) -> XMLNode {
        guard case .element(let name, _, let children) = self else { return self }
        return .element(name: name, attributes: new, children: children)
    }

    /// Canonical XML for this node.
    public var xml: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .text(let s):
            out += XMLNode.escapeText(s)
        case .element(let name, let attributes, let children):
            out += "<" + name
            for key in attributes.keys.sorted() {
                out += " \(key)=\"\(XMLNode.escapeAttribute(attributes[key]!))\""
            }
            if children.isEmpty {
                out += "/>"
            } else {
                out += ">"
                for child in children { child.write(to: &out) }
                out += "</\(name)>"
            }
        }
    }

    /// Escapes text content. Newlines stay as they are; carriage returns
    /// (soft line breaks in older wxMaxima files) become character references,
    /// because XML parsers turn a literal one into a newline.
    public static func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\r": out += "&#x0D;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    /// Escapes an attribute value; tabs and newlines become character
    /// references so XML parsers keep them.
    public static func escapeAttribute(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t": out += "&#x09;"
            case "\n": out += "&#x0A;"
            case "\r": out += "&#x0D;"
            default: out.append(c)
            }
        }
        return out
    }
}

public enum XMLTreeError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformed(line: Int, column: Int, message: String)

    public var description: String {
        switch self {
        case let .malformed(line, column, message): "XML error at line \(line), column \(column): \(message)"
        }
    }
}

public enum XMLTree {
    /// Parses a whole document; returns the root element.
    public static func parse(_ data: Data) throws(XMLTreeError) -> XMLNode {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = builder.roots.first(where: { $0.name != nil }) else {
            throw .malformed(line: parser.lineNumber, column: parser.columnNumber,
                             message: parser.parserError?.localizedDescription ?? "no root element")
        }
        return root
    }

    /// Parses a fragment (any number of top-level nodes).
    public static func parseFragment(_ xml: String) throws(XMLTreeError) -> [XMLNode] {
        let root = try parse(Data("<macsima-fragment>\(xml)</macsima-fragment>".utf8))
        return root.children
    }

    /// `xml` in canonical form, or unchanged if it does not parse.
    public static func canonical(_ xml: String) -> String {
        guard let nodes = try? parseFragment(xml) else { return xml }
        return nodes.map(\.xml).joined()
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [(name: String, attributes: [String: String], children: [XMLNode])] = []
        var roots: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            stack.append((name, attributes, []))
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard let top = stack.popLast() else { return }
            add(.element(name: top.name, attributes: top.attributes, children: top.children))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { addText(string) }

        func parser(_ parser: XMLParser, foundCDATA block: Data) { addText(String(decoding: block, as: UTF8.self)) }

        private func addText(_ string: String) {
            guard !stack.isEmpty else { return }
            if case .text(let previous)? = stack[stack.count - 1].children.last {
                stack[stack.count - 1].children[stack[stack.count - 1].children.count - 1] = .text(previous + string)
            } else {
                stack[stack.count - 1].children.append(.text(string))
            }
        }

        private func add(_ node: XMLNode) {
            if stack.isEmpty { roots.append(node) } else { stack[stack.count - 1].children.append(node) }
        }
    }
}
