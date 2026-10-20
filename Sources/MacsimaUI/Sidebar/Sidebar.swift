// SPDX-License-Identifier: GPL-2.0-or-later

import MaximaKit
import SwiftUI
import WorksheetKit

/// The window's sidebar on the right: one of three panels.
public enum SidebarTab: String, CaseIterable, Sendable {
    case contents, variables, manual

    var title: String {
        switch self {
        case .contents: "Contents"
        case .variables: "Variables"
        case .manual: "Manual"
        }
    }
}

/// The variables panel's watch list and the values Maxima last sent.
/// The list is the worksheet's (saved in the file, as wxMaxima does).
@MainActor
@Observable
public final class VariablesModel {
    public private(set) var names: [String] = []
    public private(set) var values: [String: WatchedValue] = [:]
    /// A value query is out and not answered yet.
    public private(set) var isUpdating = false

    /// The list changed: into the worksheet.
    @ObservationIgnored var onChange: (([String]) -> Void)?
    /// Asks this window's Maxima for values, or for the names in `values`; false when it isn't running.
    @ObservationIgnored var askValues: (([String]) -> Bool)?
    @ObservationIgnored var askNames: (() -> Bool)?

    init() {}

    /// The worksheet's list, when the file is read.
    func load(_ list: [String]) {
        names = list
        values = [:]
    }

    /// A Maxima name: letters, digits, `_` and `%`, not starting with a digit.
    static func isName(_ s: String) -> Bool { s.wholeMatch(of: /[%A-Za-z_][%A-Za-z_0-9]*/) != nil }

    /// Adds names (trimmed; invalid and repeated ones are skipped). False when none was added.
    @discardableResult
    public func add(_ new: [String]) -> Bool {
        let added = new.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { Self.isName($0) }
            .reduce(into: [String]()) { list, name in if !names.contains(name), !list.contains(name) { list.append(name) } }
        guard !added.isEmpty else { return false }
        names += added
        onChange?(names)
        ask(added)
        return true
    }

    public func remove(_ name: String) {
        names.removeAll { $0 == name }
        values[name] = nil
        onChange?(names)
    }

    public func removeAll() {
        names = []
        values = [:]
        onChange?(names)
    }

    /// Add All: every variable the user has given a value (Maxima's `values`).
    public func addAll() { _ = askNames?() }

    /// After an evaluation, or when Maxima starts.
    public func refresh() { ask(names) }

    private func ask(_ list: [String]) {
        guard !list.isEmpty else { return }
        if askValues?(list) == true { isUpdating = true }
    }

    func received(_ reply: [WatchedValue]) {
        isUpdating = false
        for value in reply where names.contains(value.name) { values[value.name] = value }
    }

    func receivedNames(_ list: [String]) { add(list) }
}

struct SidebarView: View {
    let controller: WorksheetController

    var body: some View {
        @Bindable var controller = controller
        VStack(spacing: 0) {
            Picker("Panel", selection: $controller.sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .accessibilityIdentifier("sidebar-tabs")
            switch controller.sidebarTab {
            case .contents: ContentsPanel(controller: controller)
            case .variables: VariablesPanel(model: controller.variables, maximaBusy: controller.sessionState != .idle)
            case .manual: HelpPanel(help: controller.help, maximaBusy: controller.sessionState != .idle)
            }
        }
        .inspectorColumnWidth(min: 280, ideal: 480, max: 900)
    }
}

/// The worksheet's headings; a click goes to the heading (unfolding what
/// hides it). The section the focused cell is in is marked.
struct ContentsPanel: View {
    let controller: WorksheetController

    var body: some View {
        let sheet = controller.document.worksheet
        let headings = sheet.cells.indices.filter { sheet.cells[$0].kind.isHeading }
        let current = controller.focusedCell.flatMap { id in
            sheet.index(of: id).flatMap { i in headings.last { $0 <= i } }
        }
        if headings.isEmpty {
            Text("No headings yet. Title, section and subsection cells (⌘2, ⌘3, ⌘4) show up here.")
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(headings, id: \.self) { i in
                let cell = sheet.cells[i]
                Button { controller.focus(cell.id, caret: .end) } label: {
                    HStack(spacing: 6) {
                        Text(Self.title(of: cell))
                            .font(cell.kind == .title ? .headline : cell.kind == .section ? .body.weight(.medium) : .body)
                            .lineLimit(1)
                        if cell.isFolded {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                .help("Folded")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(Self.level(cell.kind)) * 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(current == i ? Color.accentColor.opacity(0.15) : Color.clear)
                .accessibilityIdentifier("contents-\(i)")
            }
            .listStyle(.sidebar)
        }
    }

    static func title(of cell: Cell) -> String {
        let line = cell.input.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? "Untitled \(cell.kind.displayName.lowercased())" : line
    }

    static func level(_ kind: CellKind) -> Int {
        switch kind {
        case .title: 0
        case .section: 1
        case .subsection: 2
        case .subsubsection: 3
        case .heading5: 4
        default: 5
        }
    }
}

/// The watch list: names and values, refreshed after each evaluation.
struct VariablesPanel: View {
    let model: VariablesModel
    let maximaBusy: Bool
    @State private var newName = ""
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Watch a variable", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if model.add(newName.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)) {
                            newName = ""
                        } else {
                            NSSound.beep()
                        }
                    }
                    .accessibilityIdentifier("watch-field")
                Button("Add All") { model.addAll() }
                    .help("Watch every variable that has a value (Maxima's values list)")
            }
            .padding(10)
            Divider()
            if model.names.isEmpty {
                Text("Type a name above to watch its value. Values are updated after each evaluation.")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(model.names, id: \.self, selection: $selection) { name in
                    row(name, model.values[name])
                        .contextMenu {
                            if let value = model.values[name], value.kind != .unbound {
                                Button("Copy Value") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(value.text, forType: .string)
                                }
                            }
                            Button("Stop Watching") { model.remove(name) }
                        }
                }
                .onDeleteCommand { if let selection { model.remove(selection) } }
                .accessibilityIdentifier("watch-list")
                if maximaBusy {
                    Text("Values are updated when Maxima is idle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
    }

    private func row(_ name: String, _ value: WatchedValue?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(.body, design: .monospaced).weight(.semibold))
            Group {
                switch value?.kind {
                case nil: Text("…").foregroundStyle(.tertiary)
                case .unbound: Text("no value").foregroundStyle(.tertiary).italic()
                case .error: Text(value!.text).foregroundStyle(.red)
                case .function, .value:
                    Text(value!.text + (value!.isCut ? " …" : ""))
                        .foregroundStyle(value!.kind == .function ? .secondary : .primary)
                }
            }
            .font(.system(.callout, design: .monospaced))
            .lineLimit(4)
            .textSelection(.enabled)
            .help(value.map { $0.isCut ? $0.text + " … (cut at 4000 characters)" : $0.text } ?? "")
        }
        .padding(.vertical, 2)
    }
}
