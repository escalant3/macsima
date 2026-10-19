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
        case .image(let data, let format, let label, _):
            if let image = ImageDecoding.image(data, format: format) {
                ImageOutputView(image: image, label: label)
            }
        case .animation(let frames, let format, let label, let attributes):
            // A container, so its controls keep their own identifiers.
            AnimationOutputView(frames: frames, format: format, label: label, attributes: attributes)
                .accessibilityElement(children: .contain)
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
            ForEach(OutputCopy.Kind.allCases, id: \.self) { kind in
                Button(kind.title) { OutputCopy.copy(xml, as: kind, scale: scale) }
            }
            Divider()
            Button(live ? "Show as Image" : "Select Math") { live.toggle() }
        }
    }
}

/// Copying one math output: as Maxima input, LaTeX, MathML or a picture.
@MainActor
enum OutputCopy {
    static var pasteboard: NSPasteboard { CellClipboard.pasteboard }

    enum Kind: String, CaseIterable {
        case input, latex, mathml, image

        var title: String {
            switch self {
            case .input: "Copy as Maxima Input"
            case .latex: "Copy as LaTeX"
            case .mathml: "Copy MathML"
            case .image: "Copy as Image"
            }
        }
    }

    static func copy(_ xml: String, as kind: Kind, scale: CGFloat) {
        let out = TranslationCache.shared.translate(xml)
        switch kind {
        case .input: copy(out.plainText)
        case .latex: copy(LaTeXTranslator.translate(xml) ?? out.plainText)
        case .mathml: copy(out.mathML)
        case .image: copyImage(mathML: out.mathML, scale: scale)
        }
    }

    static func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// The math alone, without its label, dark on a clear background (for
    /// pasting into documents), as PNG and TIFF.
    static func copyImage(mathML: String, scale: CGFloat) {
        Task { @MainActor in
            guard let rendered = await MathSnapshotRenderer.shared.render(mathML: mathML, label: nil, dark: false,
                                                                         scale: scale, labelColumn: false)
            else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects([rendered.image])
            if let tiff = rendered.image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                pasteboard.setData(png, forType: .png)
            }
        }
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
