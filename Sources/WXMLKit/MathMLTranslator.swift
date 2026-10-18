// SPDX-License-Identifier: GPL-2.0-or-later
//
// The meaning of each tag follows what wxMathML.lisp prints (fixtures 01-31)
// and how wxMaxima's MathParser.cpp reads it; wxMaxima is Copyright (C)
// Andrej Vodopivec, Gunter Koenigsmann and the wxMaxima developers,
// GPL-2.0-or-later.

import Foundation

/// One translated math chunk.
public struct MathOutput: Equatable, Sendable {
    /// The output label without parentheses, such as `%o3` or `%t1`.
    public var label: String?
    /// Standard MathML (`<math>…</math>`), or empty when the chunk held only an image.
    public var mathML: String
    /// Files named by `img` tags (plots).
    public var imagePaths: [String]
    /// Tags the translator does not know; rendered as their text content.
    public var unknownTags: [String]
    /// A linear text form for copying.
    public var plainText: String
    /// False when the XML did not parse; `mathML` then holds the raw text.
    public var wellFormed: Bool
}

public enum MathMLTranslator {
    /// Every tag the translator handles. Anything else is "unknown".
    public static let knownTags: Set<String> = [
        "math", "mth", "mrow", "lbl", "mi", "mn", "mo", "st", "t", "fnm", "fn", "p", "q", "mfrac",
        "msup", "msub", "munder", "ie", "mmultiscripts", "mprescripts", "none", "tb", "mtr", "mtd",
        "sm", "in", "lm", "d", "at", "hl", "cj", "a", "g", "s", "h", "mspace", "img",
    ]

    public static func translate(_ xml: String) -> MathOutput {
        guard let root = MathXMLParser.parse(xml) else {
            let text = stripTags(xml)
            return MathOutput(label: nil, mathML: "<math><mtext>\(escape(text))</mtext></math>", imagePaths: [],
                              unknownTags: [], plainText: text, wellFormed: false)
        }
        var context = Context()
        let body = context.emit(root)
        let math = body.isEmpty ? "" : "<math display=\"block\">\(body)</math>"
        let plain = PlainText.of(root).trimmingCharacters(in: .whitespaces)
        return MathOutput(label: context.label, mathML: math,
                          imagePaths: context.imagePaths, unknownTags: context.unknown.sorted(),
                          plainText: plain, wellFormed: true)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func stripTags(_ xml: String) -> String {
        var out = ""
        var inTag = false
        for c in xml {
            if c == "<" { inTag = true } else if c == ">" { inTag = false } else if !inTag { out.append(c) }
        }
        return out
    }
}

private struct Context {
    var label: String?
    var imagePaths: [String] = []
    var unknown: Set<String> = []

    mutating func emit(_ node: MathNode) -> String {
        guard case .element(let name, let attrs, let children) = node else {
            let text = node.textContent
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "<mtext>\(esc(text))</mtext>"
        }
        let kids = node.elementChildren
        switch name {
        case "mrow" where attrs["list"] == "true" || attrs["set"] == "true":
            // List and set brackets arrive as <t listdelim="true">; size them like parens.
            let outer = fencesStretch
            fencesStretch = Self.isTall(node)
            defer { fencesStretch = outer }
            return row(children)
        case "math", "mth", "mrow", "d":
            return row(children)
        case "lbl":
            let raw = attrs["altCopy"] ?? node.textContent
            label = raw.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            return ""
        case "mi":
            return identifier(node.textContent)
        case "mn":
            return "<mn>\(esc(node.textContent))</mn>"
        case "mo":
            return "<mo>\(esc(Self.operatorText(node.textContent)))</mo>"
        case "st":
            return "<mtext>\(esc(node.textContent))</mtext>"
        case "t":
            if attrs["listdelim"] == "true" { return Self.fence(node.textContent, stretchy: fencesStretch) }
            return "<mtext>\(esc(node.textContent))</mtext>"
        case "fnm":
            return "<mi>\(esc(node.textContent))</mi>"
        case "fn":
            guard let head = kids.first else { return row(children) }
            let name = head.name == "g" ? greek(head.textContent, asFunction: true) : emit(head)
            return "<mrow>\(name)<mo>&#x2061;</mo>\(kids.dropFirst().map { emit($0) }.joined())</mrow>"
        case "p":
            // print="no" only drops the parens from text exports (wxMaxima's
            // ParenCell::ToString); they are always drawn, e.g. around binomials.
            let tall = Self.isTall(node)
            return "<mrow>\(Self.fence("(", stretchy: tall))\(row(children))\(Self.fence(")", stretchy: tall))</mrow>"
        case "q":
            // The invisible strut gives every radical the same minimum height,
            // so √a clears the bar and √2·√π line up (WebKit sizes each
            // radical to its own content).
            return "<msqrt>\(Self.radicalStrut)\(row(children))</msqrt>"
        case "mfrac":
            guard kids.count == 2 else { return unknownElement(node) }
            let line = attrs["line"] == "no" ? " linethickness=\"0\"" : ""
            return "<mfrac\(line)>\(emit(kids[0]))\(emit(kids[1]))</mfrac>"
        case "msup":
            guard kids.count == 2 else { return unknownElement(node) }
            var exponent = emit(kids[1])
            if attrs["mat"] == "true" { exponent = "<mrow><mo>&#x27E8;</mo>\(exponent)<mo>&#x27E9;</mo></mrow>" }
            return "<msup>\(emit(kids[0]))\(exponent)</msup>"
        case "msub":
            guard kids.count == 2 else { return unknownElement(node) }
            return "<msub>\(emit(kids[0]))\(emit(kids[1]))</msub>"
        case "munder":
            guard kids.count == 2 else { return unknownElement(node) }
            // Array subscripts (x[1]) are printed as munder with an "array" lisp attribute.
            let tag = (attrs["lisp"] ?? "").contains("array") ? "msub" : "munder"
            return "<\(tag)>\(emit(kids[0]))\(emit(kids[1]))</\(tag)>"
        case "ie":
            guard kids.count == 3 else { return unknownElement(node) }
            return "<msubsup>\(emit(kids[0]))\(emit(kids[1]))\(emit(kids[2]))</msubsup>"
        case "mmultiscripts":
            return "<mmultiscripts>\(kids.map { emit($0) }.joined())</mmultiscripts>"
        case "mprescripts":
            return "<mprescripts/>"
        case "none":
            return "<none/>"
        case "tb":
            let rows = kids.map { emit($0) }.joined()
            let (open, close) = attrs["bracketParens"] == "true" ? ("(", ")") : ("[", "]")
            return "<mrow><mo>\(open)</mo><mtable>\(rows)</mtable><mo>\(close)</mo></mrow>"
        case "mtr":
            return "<mtr>\(kids.map { emit($0) }.joined())</mtr>"
        case "mtd":
            // Table cells drop display style; wxMaxima shows full-size fractions in matrices.
            return "<mtd><mrow displaystyle=\"true\">\(row(children))</mrow></mtd>"
        case "sm":
            guard kids.count == 3 else { return unknownElement(node) }
            let op = attrs["type"] == "prod" ? "&#x220F;" : "&#x2211;"
            return "<mrow><munderover><mo>\(op)</mo>\(emit(kids[0]))\(emit(kids[1]))</munderover>\(emit(kids[2]))</mrow>"
        case "in":
            if attrs["def"] == "false" {
                guard kids.count == 2 else { return unknownElement(node) }
                return "<mrow><mo>&#x222B;</mo>\(emit(kids[0]))<mspace width=\"0.2em\"/>\(emit(kids[1]))</mrow>"
            }
            guard kids.count == 4 else { return unknownElement(node) }
            return "<mrow><msubsup><mo>&#x222B;</mo>\(emit(kids[0]))\(emit(kids[1]))</msubsup>\(emit(kids[2]))<mspace width=\"0.2em\"/>\(emit(kids[3]))</mrow>"
        case "lm":
            guard kids.count == 3 else { return unknownElement(node) }
            return "<mrow><munder><mo>\(esc(kids[0].textContent))</mo>\(emit(kids[1]))</munder>\(emit(kids[2]))</mrow>"
        case "at":
            guard kids.count == 2 else { return unknownElement(node) }
            return "<msub><mrow>\(emit(kids[0]))<mo stretchy=\"true\">|</mo></mrow>\(emit(kids[1]))</msub>"
        case "hl":
            return "<menclose notation=\"box\">\(row(children))</menclose>"
        case "cj":
            // WebKit draws mover accents (U+00AF, U+203E, U+0305) misplaced; menclose is clean.
            return "<menclose notation=\"top\">\(row(children))</menclose>"
        case "a":
            let tall = Self.isTall(node)
            return "<mrow>\(Self.fence("|", stretchy: tall))\(row(children))\(Self.fence("|", stretchy: tall))</mrow>"
        case "g":
            return greek(node.textContent, asFunction: false)
        case "s":
            return Self.special(node.textContent)
        case "h":
            return Self.thinSpace   // row() turns it into a dot between numbers
        case "mspace":
            return "<mspace width=\"0.4em\"/>"
        case "img":
            imagePaths.append(node.textContent.trimmingCharacters(in: .whitespacesAndNewlines))
            return ""
        default:
            return unknownElement(node)
        }
    }

    static let thinSpace = "<mspace width=\"0.17em\"/>"
    static let radicalStrut = "<mpadded width=\"0\"><mphantom><mo stretchy=\"false\">(</mo></mphantom></mpadded>"

    /// Whether list and set brackets in the current list may stretch.
    var fencesStretch = true

    /// A bracket. WebKit draws stretchy fences around short content raised
    /// above the baseline, so they stretch only around tall content.
    static func fence(_ text: String, stretchy: Bool) -> String {
        stretchy ? "<mo>\(MathMLTranslator.escape(text))</mo>"
            : "<mo stretchy=\"false\">\(MathMLTranslator.escape(text))</mo>"
    }

    /// Content taller than a line of text: fractions, matrices, sums,
    /// integrals and limits, at any depth.
    static func isTall(_ node: MathNode) -> Bool {
        if let name = node.name, ["mfrac", "tb", "sm", "in", "lm", "at"].contains(name) { return true }
        return node.elementChildren.contains(where: isTall)
    }

    /// Children in an `mrow`. Hidden multiplication (`h`) is a thin space, as
    /// with wxMaxima's default "hide multiplication sign", except between two
    /// numbers (`1.5·10^-10`), where a space would read as one number, and
    /// after a differential `d`, where it is dropped.
    mutating func row(_ nodes: [MathNode]) -> String {
        let elements = nodes.filter { $0.name != nil || !$0.textContent.trimmingCharacters(in: .whitespaces).isEmpty }
        var parts: [String] = []
        for (i, node) in elements.enumerated() {
            // A differential binds to its variable: d x prints as dx (as the
            // integral's dx already does), while dx dy keeps its thin space.
            if node.name == "h", i > 0, elements[i - 1].name == "s",
               elements[i - 1].textContent == "d" {
                continue
            }
            if node.name == "h", i > 0, i + 1 < elements.count,
               Self.isNumber(elements[i - 1]), Self.isNumber(elements[i + 1]) {
                parts.append("<mo>&#x22C5;</mo>")
                continue
            }
            let part = emit(node)
            if !part.isEmpty { parts.append(part) }
        }
        if parts.isEmpty { return "" }
        return parts.count == 1 ? parts[0] : "<mrow>\(parts.joined())</mrow>"
    }

    /// A number, or a power of a number (`10^-10`).
    static func isNumber(_ node: MathNode) -> Bool {
        if node.name == "mn" { return true }
        if node.name == "msup", let base = node.elementChildren.first { return isNumber(base) }
        if node.name == "mrow", node.elementChildren.count == 1 { return isNumber(node.elementChildren[0]) }
        return false
    }

    mutating func unknownElement(_ node: MathNode) -> String {
        if let name = node.name { unknown.insert(name) }
        let text = node.textContent
        return text.isEmpty ? "" : "<mtext>\(esc(text))</mtext>"
    }

    /// `mi` holds names, but the glue also prints operators such as ` and `,
    /// ` . ` and `,` (inside `ie`) as `mi`.
    func identifier(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        let isName = trimmed == text && trimmed.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "%" || $0 == "?"
        }
        if isName { return "<mi>\(esc(trimmed))</mi>" }
        return "<mo>\(esc(Self.operatorText(trimmed)))</mo>"
    }

    func greek(_ raw: String, asFunction: Bool) -> String {
        // "%gamma" is Euler's constant, "gamma" the gamma function (wxMathML.lisp).
        if asFunction && raw == "gamma" { return "<mi mathvariant=\"normal\">&#x0393;</mi>" }
        let name = raw.hasPrefix("%") ? String(raw.dropFirst()) : raw
        guard let letter = Greek.letters[name] else { return "<mi>\(esc(raw))</mi>" }
        return "<mi>\(letter)</mi>"
    }

    static func special(_ raw: String) -> String {
        switch raw {
        case "%pi": "<mi>&#x03C0;</mi>"
        case "%e": "<mi mathvariant=\"normal\">e</mi>"
        case "%i": "<mi mathvariant=\"normal\">i</mi>"
        case "inf": "<mi mathvariant=\"normal\">&#x221E;</mi>"
        case "minf": "<mrow><mo>&#x2212;</mo><mi mathvariant=\"normal\">&#x221E;</mi></mrow>"
        case "d": "<mi mathvariant=\"normal\">d</mi>"
        default: "<mi>\(MathMLTranslator.escape(raw.hasPrefix("%") ? String(raw.dropFirst()) : raw))</mi>"
        }
    }

    static func operatorText(_ s: String) -> String {
        switch s {
        case "->": "\u{2192}"
        case "-": "\u{2212}"
        case "<=": "\u{2264}"
        case ">=": "\u{2265}"
        case "#": "\u{2260}"
        default: s
        }
    }

    func esc(_ s: String) -> String { MathMLTranslator.escape(s) }
}

enum Greek {
    static let letters: [String: String] = {
        let lower = ["alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ",
                     "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ",
                     "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π", "rho": "ρ", "sigma": "σ",
                     "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω"]
        let upper = ["Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε", "Zeta": "Ζ",
                     "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ", "Lambda": "Λ", "Mu": "Μ",
                     "Nu": "Ν", "Xi": "Ξ", "Omicron": "Ο", "Pi": "Π", "Rho": "Ρ", "Sigma": "Σ",
                     "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ", "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω"]
        return lower.merging(upper) { a, _ in a }
    }()
}

/// A linear text form, for copy and for logs.
enum PlainText {
    static func of(_ node: MathNode) -> String {
        guard case .element(let name, let attrs, let children) = node else { return node.textContent }
        let kids = node.elementChildren
        func join(_ nodes: [MathNode]) -> String { nodes.map(of).joined() }
        switch name {
        case "lbl", "img": return ""
        case "h": return "*"
        case "mspace": return " "
        case "mfrac" where kids.count == 2 && attrs["line"] == "no":
            return "binomial(\(of(kids[0])),\(of(kids[1])))"
        case "mfrac" where kids.count == 2: return "(\(of(kids[0])))/(\(of(kids[1])))"
        case "msup" where kids.count == 2: return "\(of(kids[0]))^(\(of(kids[1])))"
        case "munder" where kids.count == 2: return "\(of(kids[0]))[\(of(kids[1]))]"
        case "q": return "sqrt(\(join(children)))"
        case "p": return attrs["print"] == "no" ? join(children) : "(\(join(children)))"
        case "a": return "abs(\(join(children)))"
        case "cj": return "conjugate(\(join(children)))"
        default:
            if name != "mrow", name != "math", name != "mth", let alt = attrs["altCopy"] { return alt }
            return join(children)
        }
    }
}
