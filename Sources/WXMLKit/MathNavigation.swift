// SPDX-License-Identifier: GPL-2.0-or-later
//
// The levels the keyboard walks follow wxMaxima's OutputNavigation
// (src/worksheet/OutputNavigation.cpp, GH #2382; Copyright (C) 2026 Gunter
// Königsmann and the wxMaxima developers, GPL-2.0-or-later), written anew
// for MathTree.

import Foundation

/// An output as a tree the keyboard walks: Return goes into a part
/// (`children`), Escape out of it (`parent`), Left and Right to its
/// neighbours, Shift+Left and Right grow a run, arrows step through a
/// matrix's entries. Parts are what the mouse selects (MathSelection), and
/// the tree follows the expression, not how it was broken into lines.
///
/// Only drawn nodes are parts: those the translator tagged; untagged nodes
/// (a row around one child) are looked through. A matrix's parts are its
/// entries. A selection without a drawing of its own (an entry, the whole
/// output when it is one fraction) looks like its only part, so Return goes
/// on into that part's parts.
public struct MathNavigation: Sendable {
    public let tree: MathTree
    /// Nodes with an element of their own in the MathML.
    let shown: Set<Int>

    public init(tree: MathTree, shown: Set<Int>) {
        self.tree = tree
        self.shown = shown
    }

    /// The navigation of a translated output: shown are the nodes its
    /// tagged MathML numbers. Nil when the output has no tree.
    public init?(_ out: MathOutput) {
        guard let tree = out.tree else { return nil }
        let numbers = out.taggedMathML.matches(of: #/data-p="(\d+)"/#).compactMap { Int($0.output.1) }
        self.init(tree: tree, shown: Set(numbers))
    }

    /// The whole output.
    public var whole: MathSelection { .node(tree.rootID) }

    /// What Return selects into, in reading order; empty when there is
    /// nothing inside.
    public func children(of selection: MathSelection) -> [MathSelection] {
        chain(normalized(selection)).parts
    }

    /// The part holding this one: what Escape selects. Nil for the whole output.
    public func parent(of selection: MathSelection) -> MathSelection? {
        let s = normalized(selection)
        if s == whole { return nil }
        let start: Int
        switch s {
        case .node(let id): start = tree.parent[id]
        case .run(let p, _, _): start = p
        case .block(let t, _, _): start = t
        }
        // A run's level is the one holding its first part.
        let member: MathSelection = if case .run(_, let first, _) = s { .node(first) } else { s }
        var a = start
        while a >= 0 {
            if let holder = holder(a) {
                let (passed, parts) = chain(holder)
                if holder != s, parts.contains(member) || passed.dropFirst().contains(s) { return outermost(holder) }
            }
            a = tree.parent[a]
        }
        return whole
    }

    /// A parent that looks the same as the one holding it (a fraction that
    /// is the whole output) gives way to that one, so every Escape changes
    /// what is selected.
    func outermost(_ selection: MathSelection) -> MathSelection {
        var current = selection
        var a: Int
        switch current {
        case .node(let id): a = tree.parent[id]
        case .block(let t, _, _): a = t
        case .run(let p, _, _): a = p
        }
        while a >= 0 {
            if let holder = holder(a), holder != current {
                if chain(holder).passed.dropFirst().contains(current) { current = holder } else { break }
            }
            a = tree.parent[a]
        }
        return current
    }

    /// The level a part is one of, and where it is there (for a run, where
    /// it starts and ends). Nil for the whole output.
    public func level(of selection: MathSelection) -> (siblings: [MathSelection], first: Int, last: Int)? {
        let s = normalized(selection)
        guard let parent = parent(of: s) else { return nil }
        let siblings = children(of: parent)
        if let i = siblings.firstIndex(of: s) { return (siblings, i, i) }
        if case .run(_, let first, let last) = s,
           let i = siblings.firstIndex(of: .node(first)), let j = siblings.firstIndex(of: .node(last)) {
            return (siblings, i, j)
        }
        return nil
    }

    /// Left and Right: the neighbouring part, or the same at the level's end.
    /// From a run, the part beyond its left or right end.
    public func neighbour(of selection: MathSelection, right: Bool) -> MathSelection {
        guard let (siblings, first, last) = level(of: selection) else { return selection }
        return right ? siblings[min(last + 1, siblings.count - 1)] : siblings[max(first - 1, 0)]
    }

    /// Shift+Left and Right: the run from `anchor` (a part of the same
    /// level, where the growing started) to one part further. Parts that
    /// are not a sequence (a fraction's numerator and denominator) and
    /// matrix entries (see `step`) stay as they are.
    public func extend(_ selection: MathSelection, anchor: MathSelection, right: Bool) -> MathSelection {
        guard let (siblings, first, last) = level(of: selection),
              let a = siblings.firstIndex(of: normalized(anchor)) else { return selection }
        let end = a == first ? last : first
        let moving = right ? min(end + 1, siblings.count - 1) : max(end - 1, 0)
        let lo = min(a, moving), hi = max(a, moving)
        if lo == hi { return siblings[lo] }
        guard case .node(let f) = siblings[lo], case .node(let l) = siblings[hi],
              tree.parent[f] == tree.parent[l], tree.parent[f] >= 0,
              let name = tree.nodes[tree.parent[f]].name, MathLayout.rows.contains(name) else { return selection }
        return .run(parent: tree.parent[f], first: f, last: l)
    }

    /// Arrows in a matrix: the entry moved by rows and columns, staying
    /// inside the matrix. With `anchor`, the block from the anchor's entry
    /// to the moved far corner (Shift+arrows). Nil when the selection is no
    /// entry or block.
    public func step(_ selection: MathSelection, rows dr: Int, columns dc: Int,
                     anchor: (row: Int, column: Int)? = nil) -> MathSelection? {
        guard case .block(let t, let rows, let columns) = normalized(selection) else { return nil }
        let size = matrixSize(t)
        guard size.rows > 0, size.columns > 0 else { return nil }
        let corner = (row: anchor.map { $0.row == rows.lowerBound ? rows.upperBound : rows.lowerBound } ?? rows.lowerBound,
                      column: anchor.map { $0.column == columns.lowerBound ? columns.upperBound : columns.lowerBound }
                        ?? columns.lowerBound)
        let moved = (row: min(max(corner.row + dr, 0), size.rows - 1),
                     column: min(max(corner.column + dc, 0), size.columns - 1))
        let from = anchor ?? moved
        return .block(table: t, rows: min(from.row, moved.row)...max(from.row, moved.row),
                      columns: min(from.column, moved.column)...max(from.column, moved.column))
    }

    /// One entry of a matrix.
    public func isEntry(_ selection: MathSelection) -> Bool {
        if case .block(_, let rows, let columns) = normalized(selection) { return rows.count == 1 && columns.count == 1 }
        return false
    }

    // MARK: - Parts

    /// The parts of a selection, going on into its only part while the
    /// selection has no drawing of its own; `passed` are the selections
    /// gone through, the selection first.
    func chain(_ selection: MathSelection) -> (passed: [MathSelection], parts: [MathSelection]) {
        var current = selection
        var passed = [current]
        var parts = directChildren(of: current)
        while parts.count == 1, !drawsItself(current), passed.count < MathMLTranslator.maxDepth {
            current = parts[0]
            passed.append(current)
            parts = directChildren(of: current)
        }
        return (passed, parts)
    }

    func drawsItself(_ selection: MathSelection) -> Bool {
        switch selection {
        case .node(let id): shown.contains(id)
        case .run: true
        case .block(_, let rows, let columns): rows.count > 1 || columns.count > 1
        }
    }

    func directChildren(of selection: MathSelection) -> [MathSelection] {
        switch selection {
        case .node(let id):
            return tree.nodes[id].name == "tb" ? entries(of: id) : parts(below: id)
        case .run(let p, let first, let last):
            return parts(below: p).filter {
                guard case .node(let n) = $0 else { return false }
                return tree.place[n] >= tree.place[first] && tree.place[n] <= tree.place[last]
            }
        case .block(let t, let rows, let columns):
            guard rows.count == 1, columns.count == 1, let mtd = entry(t, rows.lowerBound, columns.lowerBound)
            else { return [] }
            return parts(below: mtd)
        }
    }

    /// Shown nodes below `id`, looking through unshown ones. A matrix is
    /// one part, whatever its parts. A limit's "lim" is a label, not a part
    /// (wxMaxima's PartsOf).
    func parts(below id: Int) -> [MathSelection] {
        var out: [MathSelection] = []
        var stack = Array(tree.children[id].reversed())
        if ["lm", "limit"].contains(tree.nodes[id].name ?? ""), !stack.isEmpty { stack.removeLast() }
        while let n = stack.popLast() {
            if tree.nodes[n].name == "tb" || shown.contains(n) {
                out.append(.node(n))
            } else {
                stack.append(contentsOf: tree.children[n].reversed())
            }
        }
        return out
    }

    /// What a node is as a parent: an entry for a matrix cell, the node
    /// when it is drawn or the whole output, else nothing (a matrix row, a
    /// row looked through).
    func holder(_ id: Int) -> MathSelection? {
        switch tree.nodes[id].name {
        case "mtr": nil
        case "mtd": normalized(.node(id))
        default: shown.contains(id) || id == tree.rootID || tree.nodes[id].name == "tb" ? .node(id) : nil
        }
    }

    /// A matrix cell's node is its entry.
    func normalized(_ selection: MathSelection) -> MathSelection {
        guard case .node(let id) = selection, tree.nodes[id].name == "mtd",
              let row = Optional(tree.parent[id]), row >= 0, tree.parent[row] >= 0 else { return selection }
        let table = tree.parent[row]
        guard let r = rows(of: table).firstIndex(of: row),
              let c = tree.children[row].filter({ tree.nodes[$0].name == "mtd" }).firstIndex(of: id) else { return selection }
        return .block(table: table, rows: r...r, columns: c...c)
    }

    func entries(of table: Int) -> [MathSelection] {
        let size = matrixSize(table)
        var out: [MathSelection] = []
        for r in 0..<size.rows {
            for c in 0..<size.columns where entry(table, r, c) != nil {
                out.append(.block(table: table, rows: r...r, columns: c...c))
            }
        }
        return out
    }

    func rows(of table: Int) -> [Int] { tree.children[table].filter { tree.nodes[$0].name == "mtr" } }

    func entry(_ table: Int, _ row: Int, _ column: Int) -> Int? {
        let rows = rows(of: table)
        guard rows.indices.contains(row) else { return nil }
        let cells = tree.children[rows[row]].filter { tree.nodes[$0].name == "mtd" }
        return cells.indices.contains(column) ? cells[column] : nil
    }

    func matrixSize(_ table: Int) -> (rows: Int, columns: Int) {
        let rows = rows(of: table)
        let columns = rows.map { tree.children[$0].filter { tree.nodes[$0].name == "mtd" }.count }.max() ?? 0
        return (rows.count, columns)
    }
}
