// SPDX-License-Identifier: GPL-2.0-or-later

import MaximaKit
import SwiftUI
import WorksheetKit

/// The content of one document window: the worksheet's cells in a lazy stack.
struct WorksheetWindow: View {
    @ObservedObject var document: WorksheetDocument
    @State private var controller: WorksheetController
    @Environment(\.undoManager) private var undoManager

    init(document: WorksheetDocument) {
        self.document = document
        _controller = State(initialValue: WorksheetController(document: document))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(document.worksheet.cells.enumerated()), id: \.element.id) { index, cell in
                        CellView(
                            cell: cell,
                            index: index,
                            isFocused: controller.focusedCell == cell.id,
                            focusRequest: controller.focusRequest,
                            caretRequest: controller.caretRequest,
                            makeEditor: { controller.editor(for: cell.id) }
                        )
                        .id(cell.id)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
            }
            .onChange(of: controller.focusRequest) {
                if let id = controller.focusedCell { withAnimation { proxy.scrollTo(id) } }
            }
            .onChange(of: controller.scrollRequest?.serial) {
                guard let id = controller.scrollRequest?.cell else { return }
                proxy.scrollTo(id)
                // Once the cell is laid out: a long cell scrolls on to the match.
                DispatchQueue.main.async { controller.afterScroll?() }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if controller.find.isVisible { FindBar(find: controller.find) }
                if !document.openWarnings.isEmpty {
                    OpenWarningsBanner(warnings: document.openWarnings) { document.openWarnings = [] }
                }
            }
        }
        .background {
            WindowReader { window in
                controller.window = window
                controller.watchClose(of: window)
                controller.markEdited = { [weak window] in
                    (window?.windowController?.document as? NSDocument)?.updateChangeCount(.changeDone)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = controller.statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
        .toolbar { WorksheetToolbar(controller: controller) }
        .environment(controller)
        .task { await controller.start() }
        .focusedSceneValue(controller)
        .onAppear {
            controller.becameKey()
            controller.undoManager = undoManager
            if controller.focusedCell == nil { controller.focusedCell = document.worksheet.cells.first?.id }
        }
        .onChange(of: undoManager) { _, new in controller.undoManager = new }
        .onChange(of: controller.asking) { _, asking in
            // The answer field had the focus; give it back to the current cell.
            if asking == nil { controller.requestFocus() }
        }
        .onChange(of: document.worksheet.cells.map(\.id)) { old, new in
            // The focused cell went away (undo, delete): focus its neighbour.
            controller.find.documentChanged()
            guard let id = controller.focusedCell, !new.contains(id) else { return }
            let index = old.firstIndex(of: id) ?? new.count
            controller.focusedCell = new.isEmpty ? nil : new[min(max(0, index - 1), new.count - 1)]
        }
    }
}

/// Session state, a busy indicator, Interrupt and Restart.
struct WorksheetToolbar: ToolbarContent {
    let controller: WorksheetController

    var body: some ToolbarContent {
        ToolbarItem(placement: .status) {
            HStack(spacing: 6) {
                if controller.sessionState == .busy || controller.sessionState == .starting {
                    ProgressView().controlSize(.small)
                }
                Text(Self.label(controller.sessionState))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("session-state")
            }
        }
        ToolbarItem {
            Button("Interrupt", systemImage: "stop.fill") { controller.interrupt() }
                .help("Interrupt (⌘.)")
                .disabled(![.busy, .question, .debugger].contains(controller.sessionState))
        }
        ToolbarItem {
            Button("Restart Maxima", systemImage: "arrow.clockwise") { controller.restart() }
                .help("Restart Maxima")
        }
    }

    static func label(_ state: SessionState) -> String {
        switch state {
        case .starting, .authenticating, .configuring: "Starting Maxima…"
        case .idle: "Ready"
        case .busy: "Evaluating…"
        case .question: "Waiting for an answer"
        case .debugger: "In the debugger"
        case .lisp: "Lisp mode"
        case .dead: "Maxima not running"
        }
    }
}

/// What the reader kept from a file without being able to show it.
struct OpenWarningsBanner: View {
    let warnings: [String]
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Parts of this file are kept but not shown. They are saved back unchanged.")
                    .font(.callout.weight(.medium))
                ForEach(warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button("Dismiss", action: dismiss).controlSize(.small)
        }
        .padding(10)
        .background(.bar)
    }
}
