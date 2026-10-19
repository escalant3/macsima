// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MaximaKit
import SwiftUI
import WorksheetKit
import WXMLKit

/// One output of a code cell.
struct OutputView: View {
    let output: Output
    var cellID: UUID?
    @Environment(\.worksheetScale) private var scale

    var body: some View {
        switch output {
        case .math(let xml):
            MathOutputItem(xml: xml)
        case .text(let text) where text.isEmpty:
            EmptyView()   // a statement's text run with nothing in it yet
        case .text(let text):
            MessageText(text: text, isError: false)
        case .error(_, let message):
            MessageText(text: message.isEmpty ? "Error (see the output above)" : message, isError: true)
        case .image(let data, _, let label, _):
            if let image = NSImage(data: data) {
                ImageOutputView(image: image, label: label)
            }
        case .question(let prompt, let answer):
            // The answer follows the question on its line, as in wxMaxima.
            HStack(alignment: .center, spacing: 8) {
                MathOutputItem(xml: prompt, wraps: false)
                    .fixedSize(horizontal: true, vertical: false)
                if let answer {
                    Text(answer)
                        .font(.system(size: WorksheetMetrics(scale: scale).answerFontSize, design: .monospaced))
                        .textSelection(.enabled)
                } else if let cellID {
                    AnswerField(cellID: cellID)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Plain output text or an error message. A message wxMaxima can explain
/// gets its yellow marker, the explanation as a tooltip, and a button that
/// shows it.
struct MessageText: View {
    let text: String
    let isError: Bool
    @State private var showsExplanation = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.worksheetScale) private var scale

    var body: some View {
        let explanation = MessageExplanations.explanation(for: text)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(.system(size: WorksheetMetrics(scale: scale).outputFontSize, design: .monospaced))
                .foregroundStyle(isError ? Color.red : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, explanation == nil ? 0 : 3)
                .background {
                    if explanation != nil {
                        // Lighter on dark backgrounds, where a strong yellow turns the red text muddy.
                        RoundedRectangle(cornerRadius: 3).fill(Color.yellow.opacity(scheme == .dark ? 0.14 : 0.28))
                    }
                }
                .help(explanation ?? "")
            if let explanation {
                Button("Explain", systemImage: "lightbulb") { showsExplanation.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("What this message most likely means")
                    .popover(isPresented: $showsExplanation, arrowEdge: .bottom) {
                        Text(explanation)
                            .frame(width: 320, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                    }
                    .accessibilityIdentifier("explain-message")
            }
        }
        .padding(.leading, WorksheetMetrics(scale: scale).outputIndent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A math output: a cached image from the shared renderer; clicking it swaps
/// in a live web view so the math can be selected.
struct MathOutputItem: View {
    let xml: String
    /// False keeps the math on one line.
    var wraps = true
    @State private var live = false
    @Environment(\.worksheetScale) private var scale

    var body: some View {
        let out = TranslationCache.shared.translate(xml)
        Group {
            if out.mathML.isEmpty, let label = out.label {
                // An empty result: just its label, like wxMaxima shows it.
                Text("(\(label))")
                    .font(.system(size: WorksheetMetrics(scale: scale).gutterFontSize, design: .monospaced))
                    .foregroundStyle(Color(white: 0.54))
                    .frame(width: WorksheetMetrics(scale: scale).gutterWidth, alignment: .trailing)
            } else if out.mathML.isEmpty {
                EmptyView()
            } else if live {
                MathOutputView(mathML: out.mathML, label: out.label, wraps: wraps)
            } else {
                MathImageOutputView(mathML: out.mathML, label: out.label, wraps: wraps)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(out.plainText)
        .onTapGesture { live.toggle() }
        .contextMenu {
            Button("Copy as Text") { Self.copy(out.plainText) }
            Button("Copy MathML") { Self.copy(out.mathML) }
            Button(live ? "Show as Image" : "Select Math") { live.toggle() }
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Translations of math XML, shared by every window.
@MainActor
final class TranslationCache {
    static let shared = TranslationCache()
    private var cache: [String: MathOutput] = [:]

    func translate(_ xml: String) -> MathOutput {
        if let hit = cache[xml] { return hit }
        let out = MathMLTranslator.translate(xml)
        if cache.count > 5000 { cache.removeAll() }
        cache[xml] = out
        return out
    }
}

/// The inline answer to a question Maxima is asking.
struct AnswerField: View {
    let cellID: UUID
    @Environment(WorksheetController.self) private var controller
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.worksheetScale) private var scale

    var body: some View {
        if controller.asking == cellID {
            TextField("Answer", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: WorksheetMetrics(scale: scale).answerFontSize, design: .monospaced))
                .frame(maxWidth: 320 * scale)
                .focused($focused)
                .onSubmit { controller.answer(text, for: cellID) }
                .onAppear { focused = true }
        }
    }
}
