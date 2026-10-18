// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import SwiftUI
import WorksheetKit
import WXMLKit

/// One output of a code cell.
struct OutputView: View {
    let output: Output

    var body: some View {
        switch output {
        case .math(let xml):
            MathOutputItem(xml: xml)
        case .text(let text):
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .padding(.leading, outputIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .error(_, let message):
            Text(message.isEmpty ? "Error (see the output above)" : message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .padding(.leading, outputIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image(let data, _, let label):
            if let image = NSImage(data: data) {
                ImageOutputView(image: image, label: label)
            }
        case .question(let prompt, let answer):
            VStack(alignment: .leading, spacing: 2) {
                MathOutputItem(xml: prompt)
                if let answer {
                    Text(answer)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.leading, outputIndent)
                }
            }
        }
    }
}

/// A math output: a cached image from the shared renderer; clicking it swaps
/// in a live web view so the math can be selected.
struct MathOutputItem: View {
    let xml: String
    @State private var live = false

    var body: some View {
        let out = TranslationCache.shared.translate(xml)
        Group {
            if out.mathML.isEmpty {
                EmptyView()
            } else if live {
                MathOutputView(mathML: out.mathML, label: out.label)
            } else {
                MathImageOutputView(mathML: out.mathML, label: out.label)
            }
        }
        .contentShape(Rectangle())
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
