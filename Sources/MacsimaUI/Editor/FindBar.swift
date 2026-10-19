// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import SwiftUI

/// The find bar above the worksheet: Cmd+F finds, Cmd+Opt+F also replaces.
struct FindBar: View {
    @Bindable var find: FindController

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                FindField(find: find)
                    .frame(maxWidth: 320)
                Text(find.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 80, alignment: .leading)
                    .accessibilityIdentifier("find-status")
                ControlGroup {
                    Button("Previous", systemImage: "chevron.left") { find.previous() }
                        .help("Find Previous (⇧⌘G)")
                    Button("Next", systemImage: "chevron.right") { find.next() }
                        .help("Find Next (⌘G)")
                }
                .fixedSize()
                .disabled(find.matches.isEmpty)
                Toggle("Aa", isOn: $find.caseSensitive)
                    .toggleStyle(.button)
                    .help("Match Case")
                Spacer()
                Button(find.showsReplace ? "Hide Replace" : "Replace") { find.showsReplace.toggle() }
                Button("Done") { find.close() }
            }
            if find.showsReplace {
                HStack(spacing: 8) {
                    TextField("Replace", text: $find.replacement)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .onSubmit { find.replaceCurrent() }
                        .accessibilityIdentifier("find-replacement")
                    Button("Replace") { find.replaceCurrent() }
                        .disabled(find.current == nil)
                    Button("All") { find.replaceAll() }
                        .help("Replace All")
                        .disabled(find.matches.isEmpty)
                    Spacer()
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onExitCommand { find.close() }
    }
}

/// The query field: an NSTextField, so Cmd+F can make it first responder at
/// once (FindController.show) and no keystroke typed right after Cmd+F goes
/// to the cell instead. Return finds the next match, Esc closes the bar.
struct FindField: NSViewRepresentable {
    let find: FindController

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Find"
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.stringValue = find.query
        field.setAccessibilityIdentifier("find-query")
        find.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.find = find
        // Cmd+E set the query from a selection.
        if field.stringValue != find.query { field.stringValue = find.query }
    }

    func makeCoordinator() -> Coordinator { Coordinator(find: find) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var find: FindController
        init(find: FindController) { self.find = find }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            find.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): find.next(); return true
            case #selector(NSResponder.cancelOperation(_:)): find.close(); return true
            default: return false
            }
        }
    }
}
