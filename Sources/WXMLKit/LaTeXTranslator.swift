// SPDX-License-Identifier: GPL-2.0-or-later
//
// Which LaTeX each construct becomes follows the ToTeX() methods of
// wxMaxima's cells (src/cells/*.cpp, commit 13e4aee; Copyright (C) 2004-2015
// Andrej Vodopivec, (C) 2014-2023 Gunter Königsmann and the wxMaxima
// developers, GPL-2.0-or-later), written anew to give plainer LaTeX
// (`x^{2}` instead of `{{x}^{2}}`, `\pi` instead of a Unicode π).

import Foundation

/// An output as LaTeX math (without `$` or `\[`), for pasting into a document
/// that loads amsmath (and amssymb for a few symbols). Letters without a
/// LaTeX command (é, Cyrillic) stay as \text{...}, which needs a Unicode
/// engine (LuaLaTeX, XeLaTeX) or matching fonts. Recursive like MathMLTranslator: call it on the main
/// thread, whose stack holds MathMLTranslator.maxDepth levels.
public enum LaTeXTranslator {
    public static func translate(_ xml: String) -> String? {
        guard let root = MathXMLParser.parse(xml) else { return nil }
        var depth = 0
        return tidy(tex(root, &depth))
    }

    /// Names with their own LaTeX command (as wxMaxima's FunCell::ToTeX).
    static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "sinh", "cosh", "tanh", "coth", "log", "exp",
        "arcsin", "arccos", "arctan", "det", "gcd", "max", "min", "lim", "deg",
    ]
    /// Functions LaTeX lacks a command for, set upright.
    static let operatorNames: Set<String> = [
        "asin", "acos", "atan", "acot", "asec", "acsc", "sech", "csch", "asinh", "acosh", "atanh",
        "acoth", "asech", "acsch", "erf", "erfc", "signum", "floor", "ceiling", "realpart", "imagpart",
        "carg", "abs", "sqrt", "atan2", "binomial", "gamma_incomplete",
    ]

    /// Unicode characters wxMaxima writes in its .wxmx files, as LaTeX
    /// (after the table in wxMaxima's TextCell::ToTeX).
    static let unicode: [Character: String] = {
        var t: [Character: String] = [
            "\u{221E}": "\\infty", "\u{2212}": "-", "\u{00B1}": "\\pm", "\u{2213}": "\\mp", "\u{00D7}": "\\times",
            "\u{22C5}": "\\cdot", "\u{00B7}": "\\cdot", "\u{2264}": "\\le", "\u{2265}": "\\ge", "\u{2260}": "\\neq",
            "\u{2192}": "\\to", "\u{2794}": "\\to", "\u{21D2}": "\\Rightarrow", "\u{2208}": "\\in", "\u{2203}": "\\exists",
            "\u{2204}": "\\nexists", "\u{2200}": "\\forall", "\u{2227}": "\\land", "\u{2228}": "\\lor",
            "\u{22C0}": "\\wedge", "\u{22C1}": "\\vee", "\u{00AC}": "\\lnot", "\u{22C3}": "\\cup", "\u{22C2}": "\\cap",
            "\u{222A}": "\\cup", "\u{2229}": "\\cap", "\u{2286}": "\\subseteq", "\u{2282}": "\\subset",
            "\u{2205}": "\\emptyset", "\u{210F}": "\\hbar", "\u{0127}": "\\hbar", "\u{221A}": "\\surd",
            "\u{27E8}": "\\langle", "\u{27E9}": "\\rangle", "\u{2026}": "\\dots", "\u{2202}": "\\partial",
            "\u{2211}": "\\sum", "\u{220F}": "\\prod", "\u{222B}": "\\int", "\u{00BD}": "\\frac{1}{2}",
            "\u{00B2}": "^{2}", "\u{00B3}": "^{3}", "\u{2148}": "i", "\u{2147}": "e", "\u{00B0}": "^{\\circ}",
            "\u{2061}": "", "\u{2062}": "", "\u{00A0}": "~", "\u{00B5}": "\\mu", "\u{2196}": "\\nwarrow",
            "\u{2197}": "\\nearrow", "\u{2198}": "\\searrow", "\u{2199}": "\\swarrow", "\u{2298}": "\\oslash",
            "\u{2300}": "\\varnothing",
        ]
        for (name, letter) in Greek.letters {
            if let c = letter.first, let command = greekCommand(name) { t[c] = command }
        }
        return t
    }()

    /// Math text with Unicode symbols as LaTeX commands.
    static func mathText(_ s: String) -> String {
        var out = ""
        for c in s {
            if let command = unicode[c] {
                out += command.hasPrefix("\\") ? command + " " : command
            } else if !c.isASCII {
                // Letters like ä can't stand in math mode (wxMaxima wraps them the same way).
                out += "\\text{\(c)}"
            } else {
                out.append(c)
            }
        }
        return out
    }

    private static func tex(_ node: MathNode, _ depth: inout Int) -> String {
        guard case .element(let name, let attrs, let children) = node else {
            let t = node.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "" : identifier(t)
        }
        depth += 1
        defer { depth -= 1 }
        if depth > MathMLTranslator.maxDepth { return "\\text{\(escapeText(node.textContent))}" }
        let kids = node.elementChildren
        func of(_ n: MathNode) -> String { tex(n, &depth) }
        func list(_ nodes: [MathNode]) -> String { nodes.map(of).joined(separator: " ") }
        func fenced(_ open: String, _ close: String, _ inner: String, tall: Bool) -> String {
            tall ? "\\left\(open) \(inner) \\right\(close)" : "\(open)\(inner)\(close)"
        }
        let tall = MathMLTranslator.isTallNode(node)

        switch name {
        case "lbl", "img", "editor", "line":
            return ""
        case "h":
            // Hidden multiplication: a thin space, a dot between numbers (row below).
            return "\\,"
        case "mspace":
            return "\\;"
        case "mi", "v":
            return identifier(node.textContent)
        case "mn", "n":
            return mathText(node.textContent.trimmingCharacters(in: .whitespaces))
        case "mo":
            return op(node.textContent)
        case "fnm":
            return functionName(node.textContent)
        case "st":
            return "\\text{\(escapeText(node.textContent))}"
        case "t":
            if attrs["listdelim"] == "true" { return delimiter(node.textContent) }
            return "\\text{\(escapeText(node.textContent))}"
        case "s":
            return special(node.textContent)
        case "g":
            return greek(node.textContent)
        case "math", "mth", "mrow", "r", "d":
            if attrs["list"] == "true" || attrs["set"] == "true" {
                // [ ... ] and { ... } arrive as delimiter t's; size them for tall content.
                var items = kids
                guard let first = items.first, first.attribute("listdelim") == "true",
                      let last = items.last, last.attribute("listdelim") == "true", items.count >= 2 else { return row(kids, &depth) }
                items = Array(items.dropFirst().dropLast())
                return fenced(delimiter(first.textContent), delimiter(last.textContent), row(items, &depth), tall: tall)
            }
            return row(kids, &depth)
        case "p":
            if attrs["print"] == "no" { return row(kids, &depth) }
            return fenced("(", ")", row(kids, &depth), tall: tall)
        case "q":
            return "\\sqrt{\(row(kids, &depth))}"
        case "a":
            return fenced("|", "|", row(kids, &depth), tall: tall)
        case "cj":
            return "\\overline{\(row(kids, &depth))}"
        case "hl":
            return "\\boxed{\(row(kids, &depth))}"
        case "fn":
            let content = children.filter { $0.name != nil || !$0.textContent.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let head = content.first else { return "" }
            let nameTeX: String
            if case .text(let t) = head { nameTeX = functionName(t.trimmingCharacters(in: .whitespaces)) }
            else if head.name == "fnm" || head.name == "mi" { nameTeX = functionName(head.textContent) }
            else { nameTeX = of(head) }
            return nameTeX + list(Array(content.dropFirst()))
        case "mfrac", "f":
            guard kids.count == 2 else { return list(kids) }
            if attrs["line"] == "no" { return "\\binom{\(of(kids[0]))}{\(of(kids[1]))}" }
            return "\\frac{\(of(kids[0]))}{\(of(kids[1]))}"
        case "msup", "e":
            guard kids.count == 2 else { return list(kids) }
            let exponent = attrs["mat"] == "true" ? "\\langle \(of(kids[1])) \\rangle" : of(kids[1])
            return "{\(of(kids[0]))}^{\(exponent)}"
        case "msub", "munder", "i":
            guard kids.count == 2 else { return list(kids) }
            return "{\(of(kids[0]))}_{\(of(kids[1]))}"
        case "ie":
            guard let base = kids.first else { return "" }
            var parts: [String: String] = [:]
            if kids.dropFirst().contains(where: { $0.attribute("pos") != nil }) {
                for kid in kids.dropFirst() { if let pos = kid.attribute("pos") { parts[pos] = of(kid) } }
            } else if kids.count == 3 {
                parts = ["postsub": of(kids[1]), "postsup": of(kids[2])]
            }
            var s = ""
            if parts["presub"] != nil || parts["presup"] != nil {
                s = "{}" + (parts["presub"].map { "_{\($0)}" } ?? "") + (parts["presup"].map { "^{\($0)}" } ?? "")
            }
            s += "{\(of(base))}"
            if let x = parts["postsub"] { s += "_{\(x)}" }
            if let x = parts["postsup"] { s += "^{\(x)}" }
            return s
        case "sm":
            guard kids.count == 3 else { return list(kids) }
            let command = attrs["type"] == "prod" ? "\\prod" : "\\sum"
            let over = of(kids[1])
            return "\(command)_{\(of(kids[0]))}" + (over.isEmpty ? "" : "^{\(over)}") + " " + of(kids[2])
        case "in":
            if attrs["def"] == "false", kids.count == 2 {
                return "\\int \(of(kids[0]))\\,\(of(kids[1]))"
            }
            guard kids.count == 4 else { return list(kids) }
            return "\\int_{\(of(kids[0]))}^{\(of(kids[1]))} \(of(kids[2]))\\,\(of(kids[3]))"
        case "lm", "limit":
            guard kids.count == 3 else { return list(kids) }
            // x -> 0+ is a limit from above.
            var under = kids[1].elementChildren
            var side = ""
            if let last = under.last, last.name == "mo", ["+", "-"].contains(last.textContent), under.count > 3 {
                side = "^{\(last.textContent)}"
                under.removeLast()
            }
            return "\\lim_{\(row(under, &depth))\(side)} \(of(kids[2]))"
        case "at":
            guard kids.count == 2 else { return list(kids) }
            return "\\left. \(of(kids[0])) \\right|_{\(of(kids[1]))}"
        case "tb":
            let rows = kids.filter { $0.name == "mtr" }.map { row in
                row.elementChildren.map(of).joined(separator: " & ")
            }
            let env = attrs["bracketParens"] == "true" ? "bmatrix" : attrs["straightParens"] == "true" ? "vmatrix"
                : attrs["noneParens"] == "true" ? "matrix" : attrs["angledParens"] == "true" ? "bmatrix" : "pmatrix"
            let columns = kids.filter { $0.name == "mtr" }.map(\.elementChildren.count).max() ?? 0
            if columns > 10 {
                // amsmath's matrices stop at 10 columns (MaxMatrixCols); an array doesn't.
                let fences = ["bmatrix": ("[", "]"), "vmatrix": ("|", "|"), "matrix": (".", "."), "pmatrix": ("(", ")")][env]!
                return "\\left\(fences.0) \\begin{array}{\(String(repeating: "c", count: columns))} "
                    + "\(rows.joined(separator: " \\\\ ")) \\end{array} \\right\(fences.1)"
            }
            return "\\begin{\(env)} \(rows.joined(separator: " \\\\ ")) \\end{\(env)}"
        case "mtr", "mtd":
            return list(kids)
        default:
            return list(children)
        }
    }

    /// A row: hidden multiplication between numbers is a dot.
    private static func row(_ nodes: [MathNode], _ depth: inout Int) -> String {
        var parts: [String] = []
        for (i, node) in nodes.enumerated() {
            if node.name == "h", i > 0, i + 1 < nodes.count,
               MathMLTranslator.isNumber(nodes[i - 1]), MathMLTranslator.isNumber(nodes[i + 1]) {
                parts.append("\\cdot")
                continue
            }
            // d x prints as dx.
            if node.name == "h", i > 0, nodes[i - 1].name == "s", nodes[i - 1].textContent == "d" { continue }
            let part = tex(node, &depth)
            if !part.isEmpty { parts.append(part) }
        }
        return parts.joined(separator: " ")
    }

    static func identifier(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "" }
        if t != raw || t.contains(" ") { return op(raw) }   // " and ", " or "
        let name = t.hasPrefix("%") ? String(t.dropFirst()) : t
        if let g = greekCommand(name) { return g }
        if name.count == 1 { return mathText(escapeName(name)) }
        if name.unicodeScalars.contains(where: { $0.value > 127 }) { return mathText(escapeName(name)) }
        return "\\mathit{\(escapeName(name))}"
    }

    static func functionName(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if functions.contains(t) { return "\\\(t)" }
        if operatorNames.contains(t) { return "\\operatorname{\(escapeName(t))}" }
        if t.count > 1, t.allSatisfy({ !$0.isLetter && !$0.isNumber }) { return op(t) }
        return identifier(t)
    }

    static func op(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespaces) {
        case "-", "\u{2212}": "-"
        case "*": "\\cdot"
        case ".": "\\cdot"
        case "<=", "\u{2264}": "\\le"
        case ">=", "\u{2265}": "\\ge"
        case "#", "\u{2260}": "\\neq"
        case "->", "\u{2192}": "\\to"
        case ":=": "\\mathrel{:=}"
        case "::=": "\\mathrel{::=}"
        case ":": "\\colon"
        case "and": "\\land"
        case "or": "\\lor"
        case "not": "\\lnot"
        case "^^": "^"
        case "...": "\\dots"
        case "{": "\\{"
        case "}": "\\}"
        case "%": "\\%"
        case "&": "\\&"
        case let other:
            // Keywords (if, then, else, do, ...) as upright words with space around.
            other.count > 1 && other.allSatisfy(\.isLetter) ? "\\ \\mathrm{\(other)}\\ " : mathText(other)
        }
    }

    static func delimiter(_ raw: String) -> String {
        switch raw { case "{": "\\{"; case "}": "\\}"; default: raw }
    }

    static func special(_ raw: String) -> String {
        switch raw {
        case "%pi": "\\pi"
        case "%e": "e"
        case "%i": "i"
        case "inf": "\\infty"
        case "minf": "-\\infty"
        case "d": "\\mathrm{d}"
        case "%gamma": "\\gamma"
        case "%phi": "\\varphi"
        default: identifier(raw)
        }
    }

    static func greek(_ raw: String) -> String {
        let name = raw.hasPrefix("%") ? String(raw.dropFirst()) : raw
        return greekCommand(name) ?? identifier(raw)
    }

    static func greekCommand(_ name: String) -> String? {
        guard Greek.letters[name] != nil else { return nil }
        // LaTeX has no capital letters that look like Latin ones, nor omicron.
        let latin: [String: String] = ["Alpha": "A", "Beta": "B", "Epsilon": "E", "Zeta": "Z", "Eta": "H", "Iota": "I",
                                       "Kappa": "K", "Mu": "M", "Nu": "N", "Omicron": "O", "Rho": "P", "Tau": "T",
                                       "Chi": "X", "omicron": "o"]
        if let l = latin[name] { return "\\mathrm{\(l)}" }
        return "\\\(name)"
    }

    static func escapeName(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "_": out += "\\_"
            case "%": out += "\\%"
            case "&": out += "\\&"
            case "#": out += "\\#"
            case "$": out += "\\$"
            case "\\": out += ""
            default: out.append(c)
            }
        }
        return out
    }

    static func escapeText(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\\": out += "\\textbackslash{}"
            case "{", "}", "%", "&", "#", "$", "_": out += "\\\(c)"
            case "^": out += "\\textasciicircum{}"
            case "~": out += "\\textasciitilde{}"
            default:
                if let command = unicode[c] { out += command.isEmpty ? "" : "\\ensuremath{\(command)}" } else { out.append(c) }
            }
        }
        return out
    }

    /// Collapses runs of spaces; drops spaces where LaTeX doesn't need them.
    static func tidy(_ s: String) -> String {
        var out = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        for (a, b) in [(" }", "}"), ("{ ", "{"), (" ^", "^"), (" _", "_"), ("( ", "("), (" )", ")"), (" ,", ",")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
