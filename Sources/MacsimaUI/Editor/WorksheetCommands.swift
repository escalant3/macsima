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
            // wxMaxima's Ctrl+Space and Ctrl+Shift+Space. Esc completes too,
            // as in every macOS text view; Ctrl+Space is often the input
            // source switcher, which then takes it first.
            Button("Complete Word") { controller?.complete(templatesOnly: false) }
                .keyboardShortcut(.space, modifiers: .control)
                .disabled(!(controller?.focusedCellIsCode ?? false))
            Button("Show Template") { controller?.complete(templatesOnly: true) }
                .keyboardShortcut(.space, modifiers: [.control, .shift])
                .disabled(!(controller?.focusedCellIsCode ?? false))
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
            // Not in wxMaxima: the arrow keys without stopping on outputs.
            Button("Go to Next Input") { controller?.goToInput(forward: true) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!(controller?.canGoToInput ?? false))
            Button("Go to Previous Input") { controller?.goToInput(forward: false) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!(controller?.canGoToInput ?? false))
            // Xcode's keys for the next and previous issue.
            Button("Go to Next Error") { controller?.goToError(forward: true) }
                .keyboardShortcut("'", modifiers: .command)
            Button("Go to Previous Error") { controller?.goToError(forward: false) }
                .keyboardShortcut("\"", modifiers: [.command, .shift])
            Divider()
            Button("Select All Cells") { controller?.selectAllCells() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Delete Cell") { controller?.deleteFocusedCell() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(controller?.focusedCell == nil)
        }
        CommandGroup(replacing: .importExport) {
            Menu("Export") {
                ForEach(ExportKind.allCases, id: \.self) { kind in
                    Button(kind.title) { controller?.export(kind) }
                }
            }
            .disabled(controller == nil)
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
            Divider()
            // As Xcode's inspectors: Cmd+Opt+0 the sidebar, Cmd+Opt+1... a panel.
            Button(controller?.showsSidebar == true ? "Hide Sidebar" : "Show Sidebar") {
                if let c = controller { c.showsSidebar ? (c.showsSidebar = false) : c.showSidebar(c.sidebarTab) }
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            Button("Contents") { controller?.toggleSidebar(.contents) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Variables") { controller?.toggleSidebar(.variables) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Manual") { controller?.toggleSidebar(.manual) }
                .keyboardShortcut("3", modifiers: [.command, .option])
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
        // wxMaxima's F1 for the word under the caret.
        CommandGroup(before: .help) {
            Button("Look Up in Maxima Manual") { controller?.lookUpHelp() }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey)!)), modifiers: [])
            Divider()
        }
        CommandMenu("Maxima") {
            Button("Interrupt") { controller?.interrupt() }
                .keyboardShortcut(".", modifiers: .command)
            Button("Restart Maxima") { controller?.restart() }
            Divider()
            Toggle("Debug on Error", isOn: Binding(get: { controller?.debugOnError ?? false },
                                                   set: { controller?.setDebugOnError($0) }))
            // Xcode's keys for the debugger's commands.
            let inDebugger = controller?.sessionState == .debugger
            Button("Step Over") { controller?.debugCommand(":next") }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), modifiers: [])
                .disabled(!inDebugger)
            Button("Step Into") { controller?.debugCommand(":step") }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!)), modifiers: [])
                .disabled(!inDebugger)
            Button("Continue") { controller?.debugCommand(":resume") }
                .keyboardShortcut("y", modifiers: [.command, .control])
                .disabled(!inDebugger)
            Button("Show Backtrace") { controller?.debugCommand(":bt") }
                .disabled(!inDebugger)
            Button("Leave Debugger") { controller?.debugCommand(":top") }
                .disabled(!inDebugger)
            Divider()
            Button("Return to Maxima from Lisp") { controller?.returnToMaxima() }
                .disabled(!(controller?.inLispMode ?? false) || controller?.sessionState != .lisp)
        }
    }
}

struct FormatCommand {
    let title: String
    let flag: TextFormat
    let key: KeyEquivalent?
    var modifiers: EventModifiers = .command

    static let all = [
        FormatCommand(title: String(localized: "Bold", comment: "Format menu item"), flag: .bold, key: "b"),
        FormatCommand(title: String(localized: "Italic", comment: "Format menu item"), flag: .italic, key: "i"),
        FormatCommand(title: String(localized: "Underline", comment: "Format menu item"), flag: .underline, key: "u"),
        FormatCommand(title: String(localized: "Strikethrough", comment: "Format menu item"), flag: .strikethrough, key: nil),
        FormatCommand(title: String(localized: "Superscript", comment: "Format menu item"), flag: .raised, key: "=", modifiers: [.command, .control]),
        FormatCommand(title: String(localized: "Subscript", comment: "Format menu item"), flag: .lowered, key: "-", modifiers: [.command, .control]),
    ]
}

extension CellKind {
    var displayName: String {
        switch self {
        case .title: String(localized: "Title", comment: "Cell kind")
        case .section: String(localized: "Section", comment: "Cell kind")
        case .subsection: String(localized: "Subsection", comment: "Cell kind")
        case .subsubsection: String(localized: "Subsubsection", comment: "Cell kind")
        case .heading5: String(localized: "Heading 5", comment: "Cell kind")
        case .heading6: String(localized: "Heading 6", comment: "Cell kind")
        case .text: String(localized: "Text", comment: "Cell kind")
        case .code: String(localized: "Code", comment: "Cell kind")
        case .image: String(localized: "Image", comment: "Cell kind")
        case .pageBreak: String(localized: "Page Break", comment: "Cell kind")
        case .raw: String(localized: "Unsupported Cell", comment: "Cell kind")
        }
    }
}
