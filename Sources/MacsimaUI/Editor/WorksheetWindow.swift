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
                    let sheet = document.worksheet
                    // Cells inside folded sections are left out.
                    ForEach(sheet.visibleIndices.map { (sheet.cells[$0].id, $0) }, id: \.0) { _, index in
                        let cell = sheet.cells[index]
                        CellView(
                            cell: cell,
                            index: index,
                            isFocused: controller.focusedCell == cell.id && controller.selectedCells.isEmpty,
                            isSelected: controller.selectedCells.contains(cell.id),
                            isStale: controller.staleCells.contains(cell.id),
                            onBarClick: { extend in controller.clickBar(cell.id, extend: extend) },
                            foldedCount: cell.isFolded ? sheet.foldRange(of: index).count : 0,
                            canFold: cell.kind.isHeading && !sheet.foldRange(of: index).isEmpty,
                            onToggleFold: { controller.toggleFold(cell.id) },
                            onToggleHidden: { controller.toggleHidden(cell.id) },
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
                if controller.selectionResponder == nil, let content = window.contentView {
                    let responder = CellSelectionResponder(frame: .zero)
                    responder.controller = controller
                    content.addSubview(responder)
                    controller.selectionResponder = responder
                }
                controller.watchClose(of: window)
                controller.watchScrolling(in: window)
                controller.markEdited = { [weak window] in
                    (window?.windowController?.document as? NSDocument)?.updateChangeCount(.changeDone)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(controller: controller) }
        .inspector(isPresented: $controller.showsSidebar) {
            SidebarView(controller: controller)
        }
        .environment(\.worksheetScale, controller.scale)
        .toolbar { WorksheetToolbar(controller: controller) }
        .environment(controller)
        .task { await controller.start() }
        .focusedSceneValue(controller)
        .onAppear {
            controller.becameKey()
            controller.undoManager = undoManager
            if controller.focusedCell == nil { controller.focusedCell = controller.initialFocus() }
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .accessibilityIdentifier("session-state")
            }
        }
        .sharedBackgroundVisibility(.hidden)
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

/// The bottom bar: Maxima's own messages (`wxstatusbar`, start-up
/// problems) on the left; on the right how long the running evaluation has
/// taken and Maxima's CPU use, or how long the last one took.
struct StatusBar: View {
    let controller: WorksheetController

    var body: some View {
        HStack(spacing: 12) {
            if controller.inLispMode {
                Text("Lisp mode: cells are read as Lisp.")
                    .foregroundStyle(.orange)
                Button("Return to Maxima") { controller.returnToMaxima() }
                    .controlSize(.small)
                    .disabled(controller.sessionState != .lisp)
                    .accessibilityIdentifier("return-to-maxima")
            }
            Text(controller.statusMessage ?? "")
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("status-message")
            if let since = controller.busySince {
                TimelineView(.periodic(from: since, by: 0.1)) { context in
                    Text(Self.seconds(context.date.timeIntervalSince(since)))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("status-time")
                if let cpu = controller.cpuPercent {
                    Text("CPU \(Int(cpu.rounded()))%")
                        .monospacedDigit()
                        .help("Maxima's CPU use over the last second (100% is one core)")
                }
            } else if let last = controller.lastDuration {
                Text("Last evaluation: " + Self.seconds(Double(last.components.seconds) + Double(last.components.attoseconds) / 1e18))
                    .monospacedDigit()
                    .accessibilityIdentifier("status-time")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// `0.4 s`, `12.3 s`, `2 min 05 s`.
    static func seconds(_ t: Double) -> String {
        if t < 60 { return String(format: "%.1f s", t) }
        let whole = Int(t)
        return String(format: "%d min %02d s", whole / 60, whole % 60)
    }
}
