// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI

/// Where Maxima's debugger stopped: a file and line (functions loaded from
/// a file; Maxima keeps no lines for functions typed into cells).
public struct DebugLocation: Equatable, Sendable {
    public var path: String
    public var line: Int
    /// The line's text, read from the file (up to 4 MB).
    public var source: String?

    public init(path: String, line: Int) {
        self.path = path
        self.line = line
        source = Self.read(path, line)
    }

    private static func read(_ path: String, _ line: Int) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int, size <= 4 << 20,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return line >= 1 && line <= lines.count ? lines[line - 1].trimmingCharacters(in: .whitespaces) : nil
    }
}

/// The debugger's commands under a `(dbm:N)` prompt, Xcode's keys in the
/// Maxima menu, and the field for any break command or expression.
struct DebuggerControls: View {
    let cellID: UUID
    @Environment(WorksheetController.self) private var controller
    @Environment(\.worksheetScale) private var scale
    @State private var text = ""
    @FocusState private var focused: Bool

    static let commands: [(title: String, symbol: String, command: String, help: String)] = [
        ("Step Over", "arrow.turn.down.right", ":next", "Run to the next line, over calls (F6)"),
        ("Step Into", "arrow.down.to.line", ":step", "Run to the next line, into calls (F7)"),
        ("Continue", "play.fill", ":resume", "Continue the computation (⌃⌘Y)"),
        ("Backtrace", "list.bullet.indent", ":bt", "Show the stack frames"),
        ("Leave Level", "arrow.uturn.backward", ":quit", "Leave this debugger level"),
        ("Stop", "stop.fill", ":top", "Leave the debugger and stop the computation"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Command or expression", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: WorksheetMetrics(scale: scale).answerFontSize, design: .monospaced))
                    .frame(maxWidth: 320 * scale)
                    .focused($focused)
                    .onSubmit { send(text) }
                    .onAppear { focused = true }
                    .accessibilityIdentifier("debug-field")
                ForEach(Self.commands, id: \.command) { item in
                    Button(item.title, systemImage: item.symbol) { send(item.command) }
                        .labelStyle(.iconOnly)
                        .help(item.help)
                        .accessibilityIdentifier("debug\(item.command)")
                }
            }
            if let location = controller.debugLocation {
                HStack(spacing: 8) {
                    Text("\(URL(filePath: location.path).lastPathComponent):\(location.line)")
                        .foregroundStyle(.secondary)
                        .help(location.path)
                    if let source = location.source {
                        Text(source).textSelection(.enabled)
                    }
                }
                .font(.system(size: 12 * scale, design: .monospaced))
                .accessibilityIdentifier("debug-location")
            }
        }
    }

    private func send(_ command: String) {
        let command = command.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        text = ""
        controller.debugCommand(command)
    }
}
