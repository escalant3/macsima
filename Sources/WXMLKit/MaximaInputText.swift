// SPDX-License-Identifier: GPL-2.0-or-later
//
// Ported from the ToString() methods of wxMaxima's cells (src/cells/*.cpp,
// commit 13e4aee): TextCell, FracCell, DiffCell, ExptCell, FunCell, SumCell,
// IntCell, LimitCell, AtCell, SubCell, SubSupCell, MatrCell, ParenCell,
// ListCell, SetCell, SqrtCell, AbsCell, ConjugateCell, BoxCell, NamedBoxCell:
//
//  Copyright (C) 2004-2015 Andrej Vodopivec <andrej.vodopivec@gmail.com>
//            (C) 2014-2023 Gunter Königsmann <wxMaxima@physikbuch.de>
//            (C) 2020      Kuba Ober <kuba@bertec.com>
//            (C) 2023      Wolfgang Dautermann
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.

import Foundation

/// An output as Maxima input: the linear form wxMaxima copies, which Maxima
/// reads back as the same expression. Where Macsima differs from wxMaxima:
/// sums, products, integrals and limits get a quote (`'sum(...)`), as they
/// are shown unevaluated; one-sided limits say `plus` or `minus`; exponents
/// and denominators that are fractions get brackets; matrices stay on one
/// line; quotes in strings are escaped.
public enum MaximaInputText {
    /// Characters a name must escape with a backslash (wxMaxima's
    /// Configuration::CharsNeedingQuotes).
    static let charsNeedingQuotes = Set("°,\\'\"()[]-{}^+*/&§?:;=#<>$")

    /// `quoteStrings` false gives strings as they read (print output,
    /// error messages and questions, which are text rather than values).
    public static func of(_ node: MathNode, quoteStrings: Bool = true) -> String {
        var depth = quoteStrings ? 0 : unquotedFlag
        var s = text(node, &depth)
        // A truncated Taylor series ends in "+...", which isn't input.
        if s.hasSuffix("+...") { s = String(s.dropLast(4)) }
        return s
    }

    /// Added to the depth count to say strings stay unquoted.
    private static let unquotedFlag = 1_000_000

    private static func text(_ node: MathNode, _ depth: inout Int) -> String {
        guard case .element(let name, let attrs, let children) = node else {
            let t = node.textContent
            return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : t.trimmingCharacters(in: .whitespaces)
        }
        depth += 1
        defer { depth -= 1 }
        if depth % unquotedFlag > MathMLTranslator.maxDepth { return node.textContent }
        let kids = node.elementChildren
        func of(_ n: MathNode) -> String { text(n, &depth) }
        func list(_ nodes: [MathNode]) -> String { nodes.map(of).joined() }
        func wrapped(_ n: MathNode) -> String { isCompound(n) ? "(\(of(n)))" : of(n) }

        if name != "lbl", let alt = attrs["altCopy"] { return alt }
        switch name {
        case "lbl", "img", "editor", "line", "mprescripts", "none":
            return ""
        case "h":
            return "*"
        case "mspace":
            return " "
        case "st":
            if depth >= unquotedFlag { return node.textContent }
            let escaped = node.textContent.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case "mi", "v", "fnm":
            return escapedName(node.textContent)
        case "mn", "n", "mo", "t", "s", "g":
            return leaf(node.textContent)
        case "p":
            return attrs["print"] == "no" ? list(children) : "(\(list(children)))"
        case "q":
            return "sqrt(\(list(children)))"
        case "a":
            return "abs(\(list(children)))"
        case "cj":
            return "conjugate(\(list(children)))"
        case "hl":
            if let box = attrs["boxname"] { return "box(\(list(children)),\(box))" }
            return "box(\(list(children)))"
        case "fn":
            return list(children)
        case "mfrac", "f":
            guard kids.count == 2 else { return list(children) }
            if attrs["line"] == "no" { return "binomial(\(of(kids[0])),\(of(kids[1])))" }
            let num = isCompound(kids[0]) ? "(\(of(kids[0])))" : of(kids[0])
            let den = isCompound(kids[1]) || isFraction(kids[1]) ? "(\(of(kids[1])))" : of(kids[1])
            return "\(num)/\(den)"
        case "d":
            // 'diff(base, var, order, ...): the fraction gives the variables.
            guard let frac = kids.first, frac.elementChildren.count == 2 else { return list(children) }
            var base = Array(kids.dropFirst())
            if base.first?.name == "h" { base.removeFirst() }
            var s = "'diff(" + list(base) + diffPart(frac.elementChildren[1], &depth) + ")"
            if s.hasSuffix(",1)") { s = String(s.dropLast(3)) + ")" }
            return s
        case "msup", "e":
            guard kids.count == 2 else { return list(children) }
            let caret = attrs["mat"] == "true" ? "^^" : "^"
            let exponent = isCompound(kids[1]) || isFraction(kids[1]) ? "(\(of(kids[1])))" : of(kids[1])
            return of(kids[0]) + caret + exponent
        case "msub", "munder", "i":
            guard kids.count == 2 else { return list(children) }
            return wrapped(kids[0]) + "[\(of(kids[1]))]"
        case "ie":
            var parts: [String: String] = [:]
            if kids.dropFirst().contains(where: { $0.attribute("pos") != nil }) {
                for kid in kids.dropFirst() { if let pos = kid.attribute("pos") { parts[pos] = of(kid) } }
            } else if kids.count == 3 {
                parts = ["postsub": of(kids[1]), "postsup": of(kids[2])]
            }
            guard let base = kids.first else { return "" }
            var s = wrapped(base)
            if let x = parts["presub"] { s += "[\(x)]" }
            if let x = parts["presup"] { s += "^(\(x))" }
            if let x = parts["postsub"] { s += "[\(x)]" }
            if let x = parts["postsup"] {
                let sup = kids.first { $0.attribute("pos") == "postsup" } ?? (kids.count == 3 ? kids[2] : nil)
                s += "^" + (sup.map(isCompound) == true ? "(\(x))" : x)
            }
            return s
        case "sm":
            guard kids.count == 3 else { return list(children) }
            // under: var = from; over: to (empty for lsum).
            let under = kids[0].elementChildren
            let variable = under.first.map(of) ?? ""
            let from = under.drop { $0.name != "mo" || $0.textContent != "=" }.dropFirst().map(of).joined()
            let to = of(kids[1])
            let command = attrs["type"] == "prod" ? "product" : "sum"
            if to.isEmpty { return "l\(command)(\(of(kids[2])),\(variable),\(from))" }
            return "'\(command)(\(of(kids[2])),\(variable),\(from),\(to))"
        case "in":
            if attrs["def"] == "false", kids.count == 2 {
                return "'integrate(\(of(kids[0])),\(integrationVariable(kids[1], &depth)))"
            }
            guard kids.count == 4 else { return list(children) }
            return "'integrate(\(of(kids[2])),\(integrationVariable(kids[3], &depth)),\(of(kids[0])),\(of(kids[1])))"
        case "lm", "limit":
            guard kids.count == 3 else { return list(children) }
            let under = of(kids[1])
            var variable = under, to = ""
            if let arrow = under.range(of: "->") {
                variable = String(under[..<arrow.lowerBound])
                to = String(under[arrow.upperBound...])
            }
            if to.hasSuffix("+") { to = String(to.dropLast()) + ",plus" }
            else if to.hasSuffix("-") && to.count > 1 { to = String(to.dropLast()) + ",minus" }
            return "'limit(\(of(kids[2])),\(variable),\(to))"
        case "at":
            guard kids.count == 2 else { return list(children) }
            return "at(\(of(kids[0])),\(of(kids[1])))"
        case "tb":
            let rows = kids.filter { $0.name == "mtr" }.map { row in
                "[" + row.elementChildren.map(of).joined(separator: ",") + "]"
            }
            return "matrix(\(rows.joined(separator: ",")))"
        default:
            return list(children)
        }
    }

    /// A text cell: Unicode operators back to Maxima's.
    static func leaf(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "\u{2794}", with: "-->")
            .replacingOccurrences(of: "\u{2192}", with: "->")
    }

    /// A variable or function name: characters Maxima reads as operators are
    /// escaped with a backslash, unless the name is an operator itself.
    static func escapedName(_ raw: String) -> String {
        let s = leaf(raw)
        let isOperator = raw.count <= 1 || raw.allSatisfy { $0 != " " && charsNeedingQuotes.contains($0) }
        if isOperator { return s }
        var out = ""
        for c in s {
            if charsNeedingQuotes.contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    /// Whether a list needs brackets around it: it holds an operator.
    static func isCompound(_ node: MathNode) -> Bool {
        let items = flattened(node)
        if items.count > 1 { return items.contains { ["mo", "h"].contains($0.name ?? "") } }
        return items.first.map { $0.name == "mo" } ?? false
    }

    static func isFraction(_ node: MathNode) -> Bool {
        let items = flattened(node)
        return items.count == 1 && ["mfrac", "f"].contains(items[0].name ?? "")
    }

    /// The items of a row, looking through rows of one item.
    static func flattened(_ node: MathNode) -> [MathNode] {
        var n = node
        while ["mrow", "r"].contains(n.name ?? ""), n.elementChildren.count == 1 { n = n.elementChildren[0] }
        if ["mrow", "r"].contains(n.name ?? "") { return n.elementChildren }
        return [n]
    }

    /// FracCell's derivative style: the denominator reads d x d y^2, which
    /// becomes ",x,1,y,2".
    private static func diffPart(_ denominator: MathNode, _ depth: inout Int) -> String {
        var s = ""
        for item in flattened(denominator) where item.name != "h" {
            if item.name == "s", item.textContent == "d" { continue }
            if ["msup", "e"].contains(item.name ?? ""), item.elementChildren.count == 2 {
                s += "," + text(item.elementChildren[0], &depth) + "," + text(item.elementChildren[1], &depth)
            } else {
                s += "," + text(item, &depth) + ",1"
            }
        }
        return s
    }

    /// An integral's "d x": the variable after the d.
    private static func integrationVariable(_ node: MathNode, _ depth: inout Int) -> String {
        var items = flattened(node)
        if let first = items.first, first.name == "s", first.textContent == "d" { items.removeFirst() }
        if items.first?.name == "h" { items.removeFirst() }
        return items.map { text($0, &depth) }.joined()
    }
}
