// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MaximaKit

/// The completion list under the caret: a borderless child window that never
/// takes the keyboard. The editor keeps the keys and forwards Up, Down,
/// Return, Tab and Esc (`CellTextView.handleCompletionKey`); typing goes on
/// in the editor and narrows the list.
@MainActor
final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    /// The popup the app shows, if any: one at a time.
    private(set) static weak var current: CompletionPopup?

    private(set) var items: [CompletionItem] = []
    /// The worksheet's names, gathered when the list opened.
    let worksheet: CompletionIndex
    let templatesOnly: Bool
    var onAccept: ((CompletionItem) -> Void)?

    private let panel: NSPanel
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var font: NSFont
    private static let maxRows = 10

    init(worksheet: CompletionIndex, templatesOnly: Bool, font: NSFont) {
        self.worksheet = worksheet
        self.templatesOnly = templatesOnly
        self.font = font
        panel = CompletionPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true
        panel.contentView = background

        let column = NSTableColumn(identifier: .init("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.rowHeight = ceil(font.ascender - font.descender) + 6
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.setAccessibilityIdentifier("completion-list")
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        scroll.frame = background.bounds
        scroll.autoresizingMask = [.width, .height]
        background.addSubview(scroll)
    }

    var isShown: Bool { panel.parent != nil }
    var selected: CompletionItem? { items.indices.contains(table.selectedRow) ? items[table.selectedRow] : nil }

    /// Shows `items` below the caret rectangle (screen coordinates), or
    /// above it when the screen ends below.
    func show(_ items: [CompletionItem], at caret: NSRect, in window: NSWindow) {
        if Self.current !== self { Self.current?.close() }
        Self.current = self
        self.items = items
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
        let width = min(540, max(240, items.prefix(200).map { self.width(of: $0) }.max() ?? 240))
        let height = CGFloat(min(items.count, Self.maxRows)) * table.rowHeight + 10
        let screen = window.screen?.visibleFrame ?? .infinite
        var origin = NSPoint(x: caret.minX - 6, y: caret.minY - height - 2)
        if origin.y < screen.minY { origin.y = caret.maxY + 2 }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - width)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
    }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    func move(by rows: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(0, table.selectedRow + rows), items.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func clicked() {
        if let item = selected { onAccept?(item) }
    }

    // MARK: - Rows

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: .init("cell"), owner: nil) as? NSTableCellView) ?? {
            let cell = NSTableCellView()
            cell.identifier = .init("cell")
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: RoundedRowView.inset + 7),
                field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -RoundedRowView.inset - 7),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.attributedStringValue = text(of: items[row])
        return cell
    }

    /// `integrate(expr, x)` with the arguments in grey, and "worksheet" after
    /// names that come from the worksheet.
    private func text(of item: CompletionItem) -> NSAttributedString {
        let result = NSMutableAttributedString(string: item.name, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if let template = item.template {
            let args = String(template.dropFirst(item.name.count))
                .replacing(/<([^> \n]+)>/) { String($0.1) }
            result.append(NSAttributedString(string: args, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        if item.source == .worksheet {
            let small = NSFont.systemFont(ofSize: max(9, font.pointSize - 3))
            result.append(NSAttributedString(string: "   worksheet", attributes: [.font: small, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        return result
    }

    private func width(of item: CompletionItem) -> CGFloat {
        // The row's inset and the text field's padding, both sides.
        ceil(text(of: item).size().width) + 2 * (RoundedRowView.inset + 7) + 8
    }
}

/// The selection as a rounded bar inside the panel's rounded corners, in
/// the accent colour although the panel is never key.
private final class RoundedRowView: NSTableRowView {
    static let inset: CGFloat = 5

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Self.inset, dy: 0), xRadius: 4, yRadius: 4).fill()
    }
}

/// Never the key window: the editor keeps the keyboard.
private final class CompletionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
