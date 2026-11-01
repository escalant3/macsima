// SPDX-License-Identifier: GPL-2.0-or-later
//
// Which part a click or a drag selects follows wxMaxima's
// Worksheet::SelectOutputRect, Cell::GetCellsInRect and
// MatrCell::BlockInRect (src/worksheet/Worksheet.cpp, src/cells/Cell.cpp;
// Copyright (C) 2004-2015 Andrej Vodopivec, (C) 2014-2026 Gunter Königsmann
// and the wxMaxima developers, GPL-2.0-or-later), written anew for a tree of
// rows rather than wxMaxima's lists of cells.

import CoreGraphics
import Foundation

/// The element nodes of one output, by the numbers numbered parsing gave
/// them (`data-p`), so a place on screen names the node it came from.
public struct MathTree: Sendable {
    public let root: MathNode
    /// The root's number: 0, or one past the last when the root is the row
    /// parse() wraps several top-level nodes in.
    public let rootID: Int
    /// Element nodes by number.
    public private(set) var nodes: [MathNode]
    /// Each node's parent (-1 for the root).
    public private(set) var parent: [Int]
    /// Each node's place among its parent's children, text included.
    public private(set) var place: [Int]
    /// Each node's element children with a number, in order.
    public private(set) var children: [[Int]]

    /// Nil when the tree was not parsed with numbers.
    public init?(_ root: MathNode) {
        var found: [(id: Int, node: MathNode, parent: Int, place: Int)] = []
        let rootNumber = root.attribute(MathXMLParser.numberAttribute).flatMap(Int.init)
        // Pre-order without recursion: outputs can nest 400 levels.
        var stack: [(node: MathNode, parent: Int?, place: Int)] = [(root, nil, 0)]
        var unnumbered = false
        while let (node, parentID, place) = stack.popLast().map({ ($0.node, $0.parent, $0.place) }) {
            let id: Int
            if let n = node.attribute(MathXMLParser.numberAttribute).flatMap(Int.init) {
                id = n
            } else if parentID == nil {
                id = -1   // the wrapper row; numbered below
            } else {
                unnumbered = true
                continue
            }
            found.append((id, node, parentID ?? -2, place))
            for (i, child) in node.children.enumerated().reversed() where child.name != nil {
                stack.append((child, id, i))
            }
        }
        guard !unnumbered else { return nil }
        let count = (found.map(\.id).max() ?? -1) + 1
        let rootID = rootNumber ?? count
        let size = rootNumber == nil ? count + 1 : count
        self.root = root
        self.rootID = rootID
        nodes = Array(repeating: .text(""), count: size)
        parent = Array(repeating: -1, count: size)
        place = Array(repeating: 0, count: size)
        children = Array(repeating: [], count: size)
        for entry in found {
            let id = entry.id == -1 ? rootID : entry.id
            nodes[id] = entry.node
            place[id] = entry.place
            if entry.parent != -2 {
                let p = entry.parent == -1 ? rootID : entry.parent
                parent[id] = p
                children[p].append(id)
            }
        }
    }

    /// The node and every node below it.
    public func descendants(of id: Int) -> [Int] {
        var out: [Int] = []
        var stack = [id]
        while let n = stack.popLast() {
            out.append(n)
            stack.append(contentsOf: children[n].reversed())
        }
        return out
    }
}

/// A selected part of an output.
public enum MathSelection: Hashable, Sendable {
    /// One node.
    case node(Int)
    /// Children of one node, from `first` to `last` (numbers), with
    /// everything between them.
    case run(parent: Int, first: Int, last: Int)
    /// A block of a matrix's entries (`tb`), rows and columns from 0.
    case block(table: Int, rows: ClosedRange<Int>, columns: ClosedRange<Int>)
}

/// Where each node of an output was drawn, and what a click or a drag over
/// it selects. Rectangles are in the rendered image's points.
public struct MathLayout: Sendable {
    public let tree: MathTree
    /// Each node's rectangles: its own (several when line breaking split it),
    /// or else its children's, joined line by line. Empty: not drawn.
    public private(set) var rects: [[CGRect]]

    /// `measured` holds the rectangles the page reported, by number.
    public init(tree: MathTree, measured: [Int: [CGRect]]) {
        self.tree = tree
        var rects = Array(repeating: [CGRect](), count: tree.nodes.count)
        for (id, list) in measured where rects.indices.contains(id) {
            rects[id] = list.filter { $0.width > 0 && $0.height > 0 }
        }
        // Children have higher numbers than their parents (pre-order), so
        // going down from the last number fills each node before its parent.
        for id in rects.indices.reversed() where rects[id].isEmpty {
            rects[id] = Self.byLine(tree.children[id].flatMap { rects[$0] })
        }
        // The wrapper row is numbered last but holds everything.
        if tree.rootID == rects.count - 1, rects[tree.rootID].isEmpty {
            rects[tree.rootID] = Self.byLine(tree.children[tree.rootID].flatMap { rects[$0] })
        }
        self.rects = rects
    }

    /// Rectangles joined where they share a line (overlap vertically).
    static func byLine(_ list: [CGRect]) -> [CGRect] {
        var lines: [CGRect] = []
        for r in list {
            if let i = lines.firstIndex(where: { $0.minY < r.maxY && r.minY < $0.maxY }) {
                lines[i] = lines[i].union(r)
            } else {
                lines.append(r)
            }
        }
        return lines
    }

    func intersects(_ id: Int, _ rect: CGRect) -> Bool { rects[id].contains { $0.intersects(rect) } }
    func contains(_ id: Int, _ rect: CGRect) -> Bool { rects[id].contains { $0.contains(rect) } }
    func drawn(_ id: Int) -> [Int] { tree.children[id].filter { !rects[$0].isEmpty } }

    /// What a drag over `rect` selects (a click is a drag over one point).
    /// As in wxMaxima: the smallest part that holds all of the rectangle;
    /// in it, the run of children the rectangle touches, or in a matrix the
    /// block of entries. Nil when the rectangle misses the math.
    public func select(_ rect: CGRect) -> MathSelection? {
        var c = tree.rootID
        guard intersects(c, rect) else { return nil }
        while true {
            let kids = drawn(c)
            if let k = kids.first(where: { contains($0, rect) }) {
                c = k
                continue
            }
            let hits = kids.filter { intersects($0, rect) }
            if hits.count >= 2 {
                if let block = block(in: c, rect) { return block }
                // A fraction's or a power's parts are not a sequence: over
                // two of them, the whole is selected.
                guard let name = tree.nodes[c].name, Self.rows.contains(name) else { return .node(c) }
                return .run(parent: c, first: hits[0], last: hits[hits.count - 1])
            }
            // A rectangle over one child and a gap (a fraction's bar)
            // selects the whole; one sticking out of this node goes on into
            // the child it touches.
            if hits.count == 1, !contains(c, rect) {
                c = hits[0]
                continue
            }
            return normalized(.node(c))
        }
    }

    /// Nodes whose children are drawn one after another, as a row.
    static let rows: Set<String> = ["math", "mth", "mrow", "r", "d", "mtd", "hl", "cj", "a", "p", "q"]

    /// A rectangle over several entries of a matrix, inside a table or one
    /// of its rows: the block of entries it touches.
    func block(in id: Int, _ rect: CGRect) -> MathSelection? {
        let table: Int
        switch tree.nodes[id].name {
        case "tb": table = id
        case "mtr" where tree.parent[id] >= 0 && tree.nodes[tree.parent[id]].name == "tb": table = tree.parent[id]
        default: return nil
        }
        let rows = tree.children[table].filter { tree.nodes[$0].name == "mtr" }
        var rowHits: [Int] = []
        var columnHits = Set<Int>()
        for (r, row) in rows.enumerated() where intersects(row, rect) {
            let entries = tree.children[row].filter { tree.nodes[$0].name == "mtd" }
            let touched = entries.indices.filter { intersects(entries[$0], rect) }
            if !touched.isEmpty { rowHits.append(r); columnHits.formUnion(touched) }
        }
        guard let r0 = rowHits.first, let r1 = rowHits.last, let c0 = columnHits.min(), let c1 = columnHits.max()
        else { return nil }
        return .block(table: table, rows: r0...r1, columns: c0...c1)
    }

    /// One row of a matrix is a block of that row.
    func normalized(_ selection: MathSelection) -> MathSelection {
        guard case .node(let id) = selection, tree.nodes[id].name == "mtr",
              tree.parent[id] >= 0, tree.nodes[tree.parent[id]].name == "tb" else { return selection }
        let table = tree.parent[id]
        let rows = tree.children[table].filter { tree.nodes[$0].name == "mtr" }
        guard let r = rows.firstIndex(of: id) else { return selection }
        let columns = tree.children[id].filter { tree.nodes[$0].name == "mtd" }.count
        return columns > 0 ? .block(table: table, rows: r...r, columns: 0...(columns - 1)) : selection
    }

    /// The next larger part: the node holding a run or block, or the
    /// nearest ancestor drawn larger than a node. Nil at the whole output.
    public func enclosing(_ selection: MathSelection) -> MathSelection? {
        var id: Int
        switch selection {
        case .node(let n): id = n
        case .run(let p, _, _): return .node(p)
        case .block(let t, _, _): return .node(t)
        }
        let bounds = Self.bounds(rects[id])
        while tree.parent[id] >= 0 {
            id = tree.parent[id]
            if Self.bounds(rects[id]) != bounds { return normalized(.node(id)) }
        }
        return nil
    }

    /// Where the selection is drawn, line by line.
    public func rects(of selection: MathSelection) -> [CGRect] {
        switch selection {
        case .node(let id): return rects[id]
        case .run(let p, let first, let last):
            let ids = tree.children[p].filter { tree.place[$0] >= tree.place[first] && tree.place[$0] <= tree.place[last] }
            return Self.byLine(ids.flatMap { rects[$0] })
        case .block(let t, let rowRange, let columnRange):
            let rows = tree.children[t].filter { tree.nodes[$0].name == "mtr" }
            var list: [CGRect] = []
            for r in rowRange where rows.indices.contains(r) {
                let entries = tree.children[rows[r]].filter { tree.nodes[$0].name == "mtd" }
                for c in columnRange where entries.indices.contains(c) { list += rects[entries[c]] }
            }
            return Self.byLine(list)
        }
    }

    /// The selected part as a node of its own, for copying it in any form:
    /// a run becomes a row, a block a smaller matrix, an entry a row.
    public func node(of selection: MathSelection) -> MathNode {
        switch selection {
        case .node(let id):
            let node = tree.nodes[id]
            if node.name == "mtd" { return .element(name: "mrow", attributes: [:], children: node.children) }
            return node
        case .run(let p, let first, let last):
            let all = tree.nodes[p].children
            return .element(name: "mrow", attributes: [:], children: Array(all[tree.place[first]...tree.place[last]]))
        case .block(let t, let rowRange, let columnRange):
            let table = tree.nodes[t]
            let rows = table.elementChildren.filter { $0.name == "mtr" }
            let kept: [MathNode] = rowRange.compactMap { r in
                guard rows.indices.contains(r) else { return nil }
                let entries = rows[r].elementChildren.filter { $0.name == "mtd" }
                let picked = columnRange.filter { entries.indices.contains($0) }.map { entries[$0] }
                return .element(name: "mtr", attributes: rows[r].attributes, children: picked)
            }
            return .element(name: "tb", attributes: table.attributes, children: kept)
        }
    }

    static func bounds(_ list: [CGRect]) -> CGRect {
        list.reduce(CGRect.null) { $0.union($1) }
    }
}
