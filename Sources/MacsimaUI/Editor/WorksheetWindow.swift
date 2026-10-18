// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WorksheetKit

/// The content of one document window: the worksheet's cells in a lazy stack.
struct WorksheetWindow: View {
    @ObservedObject var document: WorksheetDocument
    @State private var controller: WorksheetController
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focus: UUID?

    init(document: WorksheetDocument) {
        self.document = document
        _controller = State(initialValue: WorksheetController(document: document))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(document.worksheet.cells) { cell in
                        CellView(
                            cell: cell,
                            text: Binding(get: { cell.input }, set: { document.setInput(cell.id, $0) }),
                            focus: $focus,
                            isFocused: focus == cell.id,
                            onEvaluate: { controller.evaluate(cell.id) }
                        )
                        .id(cell.id)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
            }
            .onChange(of: controller.focusedCell) { _, id in
                if focus != id { focus = id }
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .focusedSceneValue(controller)
        .onChange(of: focus) { _, id in
            if let id {
                controller.focusedCell = id
                controller.becameKey()
            }
        }
        .onAppear {
            controller.becameKey()
            controller.undoManager = undoManager
            if controller.focusedCell == nil { controller.focusedCell = document.worksheet.cells.first?.id }
        }
        .onChange(of: undoManager) { _, new in controller.undoManager = new }
        .onChange(of: document.worksheet.cells.map(\.id)) { old, new in
            // The focused cell went away (undo, delete): focus its neighbour.
            guard let id = controller.focusedCell, !new.contains(id) else { return }
            let index = old.firstIndex(of: id) ?? new.count
            controller.focusedCell = new.isEmpty ? nil : new[min(max(0, index - 1), new.count - 1)]
        }
    }
}
