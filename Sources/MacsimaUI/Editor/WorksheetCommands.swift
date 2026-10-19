// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WorksheetKit

/// The Cell and Maxima menus. Insert shortcuts follow wxMaxima's (Ctrl+0
/// code, Ctrl+1 text, Ctrl+2 title, Ctrl+3 section, Ctrl+4 subsection),
/// with Command in place of Control.
struct WorksheetCommands: Commands {
    @FocusedValue(WorksheetController.self) private var focusedController
    /// The focused scene's controller. SwiftUI sometimes has no focused value
    /// while an AppKit text view is first responder; then the window used last.
    private var controller: WorksheetController? { focusedController ?? WorksheetController.keyController }

    var body: some Commands {
        CommandMenu("Cell") {
            Button("Evaluate Cell") { if let id = controller?.focusedCell { controller?.evaluateAndAdvance(id) } }
                .keyboardShortcut(.return, modifiers: .shift)
                .disabled(controller?.focusedCell == nil)
            Button("Evaluate All Cells") { controller?.evaluateAll() }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button("Insert Code Cell") { controller?.insertCell(.code) }
                .keyboardShortcut("0", modifiers: .command)
            Button("Insert Text Cell") { controller?.insertCell(.text) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Insert Title Cell") { controller?.insertCell(.title) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Insert Section Cell") { controller?.insertCell(.section) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Insert Subsection Cell") { controller?.insertCell(.subsection) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Insert Image…") { controller?.chooseImage() }
            Divider()
            Button("Comment or Uncomment") { controller?.toggleComment() }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(controller?.focusedCell == nil)
            Menu("Change Cell Type") {
                ForEach([CellKind.code, .text, .title, .section, .subsection], id: \.self) { kind in
                    Button(kind.displayName) { controller?.setFocusedKind(kind) }
                }
            }
            .disabled(controller?.focusedCell == nil)
            Divider()
            Button("Fold or Unfold Section") {
                if let c = controller, let id = c.focusedCell { c.toggleFold(id) }
            }
            .disabled(!(controller?.focusedCellIsHeading ?? false))
            Button("Hide or Show Cell") {
                if let c = controller, let id = c.focusedCell { c.toggleHidden(id) }
            }
            .disabled(controller?.focusedCell == nil || (controller?.focusedCellIsHeading ?? false))
            // wxMaxima's Ctrl+Alt+[ and Ctrl+Alt+], with Command for Control.
            Button("Fold All") { controller?.setAllFolded(true) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Unfold All") { controller?.setAllFolded(false) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button("Select All Cells") { controller?.selectAllCells() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Delete Cell") { controller?.deleteFocusedCell() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(controller?.focusedCell == nil)
        }
        // Replaces the Edit menu's text-view Find items, which search one cell.
        CommandGroup(replacing: .textEditing) {
            Button("Find…") { controller?.find.show(replace: false) }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find and Replace…") { controller?.find.show(replace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find Next") { controller?.find.next() }
                .keyboardShortcut("g", modifiers: .command)
            Button("Find Previous") { controller?.find.previous() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Use Selection for Find") { controller?.find.useSelection() }
                .keyboardShortcut("e", modifiers: .command)
        }
        // Zoom, saved in the file as wxMaxima does. Cmd+0 inserts a code
        // cell, so Actual Size has no shortcut.
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { controller?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { controller?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { controller?.actualSize() }
        }
        // Text cells: bold, italic, ... (wxMaxima's formats, GH #492).
        CommandMenu("Format") {
            ForEach(FormatCommand.all, id: \.title) { command in
                let button = Button(command.title) { controller?.toggleFormat(command.flag) }
                    .disabled(!(controller?.focusedCellIsText ?? false))
                if let key = command.key {
                    button.keyboardShortcut(key, modifiers: command.modifiers)
                } else {
                    button
                }
            }
        }
        CommandMenu("Maxima") {
            Button("Interrupt") { controller?.interrupt() }
                .keyboardShortcut(".", modifiers: .command)
            Button("Restart Maxima") { controller?.restart() }
        }
    }
}

struct FormatCommand {
    let title: String
    let flag: TextFormat
    let key: KeyEquivalent?
    var modifiers: EventModifiers = .command

    static let all = [
        FormatCommand(title: "Bold", flag: .bold, key: "b"),
        FormatCommand(title: "Italic", flag: .italic, key: "i"),
        FormatCommand(title: "Underline", flag: .underline, key: "u"),
        FormatCommand(title: "Strikethrough", flag: .strikethrough, key: nil),
        FormatCommand(title: "Superscript", flag: .raised, key: "=", modifiers: [.command, .control]),
        FormatCommand(title: "Subscript", flag: .lowered, key: "-", modifiers: [.command, .control]),
    ]
}

extension CellKind {
    var displayName: String {
        switch self {
        case .title: "Title"
        case .section: "Section"
        case .subsection: "Subsection"
        case .subsubsection: "Subsubsection"
        case .heading5: "Heading 5"
        case .heading6: "Heading 6"
        case .text: "Text"
        case .code: "Code"
        case .image: "Image"
        case .pageBreak: "Page Break"
        case .raw: "Unsupported Cell"
        }
    }
}
