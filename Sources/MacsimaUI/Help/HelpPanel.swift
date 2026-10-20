// SPDX-License-Identifier: GPL-2.0-or-later

import MaximaKit
import SwiftUI

/// The manual panel of one window: what `describe` would print, from this
/// window's Maxima (`MaximaSession.help`), with the manual's references as links.
@MainActor
@Observable
public final class HelpModel {
    public var isVisible = false
    /// The search field.
    public var query = ""
    public private(set) var page: HelpPage?
    /// The topic asked for and not answered yet.
    public private(set) var pending: String?
    /// Earlier topics, for Back.
    public private(set) var history: [String] = []

    /// Asks this window's Maxima; false when it isn't running.
    @ObservationIgnored var ask: ((String) -> Bool)?

    init() {}

    /// Shows the panel and looks `topic` up.
    public func lookUp(_ topic: String, remember: Bool = true) {
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        isVisible = true
        guard !topic.isEmpty else { return }
        if remember, let current = page?.topic, current != topic { history.append(current) }
        query = topic
        pending = topic
        if ask?(topic) != true {
            pending = nil
            page = HelpPage(topic: topic, error: "Maxima is not running.")
        }
    }

    public func back() {
        guard let topic = history.popLast() else { return }
        lookUp(topic, remember: false)
    }

    /// A `macsima-help` reply. Replies to topics asked before the latest are dropped.
    func received(_ reply: HelpPage) {
        guard reply.topic == pending else { return }
        pending = nil
        page = reply
    }
}

struct HelpPanel: View {
    @Bindable var help: HelpModel
    /// The window's Maxima is busy: a lookup waits until it is idle.
    let maximaBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button("Back", systemImage: "chevron.left") { help.back() }
                    .labelStyle(.iconOnly)
                    .disabled(help.history.isEmpty)
                    .help("Back")
                TextField("Maxima manual", text: $help.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { help.lookUp(help.query) }
                    .accessibilityIdentifier("help-search")
            }
            .padding(10)
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .id(help.page?.topic)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "macsima-help" else { return .systemAction }
            help.lookUp(url.absoluteString.dropFirst("macsima-help:".count).removingPercentEncoding ?? "")
            return .handled
        })
        .inspectorColumnWidth(min: 320, ideal: 520, max: 900)
    }

    @ViewBuilder private var content: some View {
        if let pending = help.pending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(maximaBusy ? "“\(pending)”: waiting until Maxima is idle…" : "Looking up “\(pending)”…")
                    .foregroundStyle(.secondary)
            }
        } else if let page = help.page {
            VStack(alignment: .leading, spacing: 16) {
                if let error = page.error {
                    Text(error).foregroundStyle(.secondary)
                } else if page.entries.isEmpty {
                    Text("No entry for “\(page.topic)” in the manual.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("help-none")
                }
                ForEach(Array(page.entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.section)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpEntryView(blocks: MaximaHelp.blocks(entry.text), topic: page.topic)
                            .accessibilityIdentifier("help-entry")
                    }
                }
                if !page.related.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.entries.isEmpty ? "Topics containing “\(page.topic)”" : "Related topics")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Self.links(page.related))
                            .font(.callout)
                    }
                }
            }
        } else {
            Text("Press F1 in a code cell to look up the name at the caret, or search above.")
                .foregroundStyle(.secondary)
        }
    }

    /// The manual's ‘quoted’ code in monospace without the quotes; plain
    /// names among it, except the page's own topic, are links to their entries.
    static func linked(_ text: String, topic: String = "") -> AttributedString {
        var result = AttributedString()
        var rest = text.startIndex
        for reference in MaximaHelp.references(in: text) {
            result += AttributedString(text[rest..<reference.range.lowerBound])
            var code = AttributedString(reference.name)
            code.font = .system(.body, design: .monospaced)
            if reference.name != topic, reference.name.wholeMatch(of: /[%A-Za-z_][%A-Za-z_0-9]*/) != nil {
                code.link = url(reference.name)
            }
            result += code
            rest = reference.range.upperBound
        }
        result += AttributedString(text[rest...])
        return result
    }

    static func links(_ names: [String]) -> AttributedString {
        var result = AttributedString()
        for (k, name) in names.enumerated() {
            if k > 0 { result += AttributedString(", ") }
            var piece = AttributedString(name)
            piece.link = url(name)
            result += piece
        }
        return result
    }

    static func url(_ topic: String) -> URL? {
        URL(string: "macsima-help:" + (topic.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? topic))
    }
}

/// One manual entry: the heading and call forms, prose that wraps to the
/// panel, examples as they are printed.
struct HelpEntryView: View {
    let blocks: [HelpBlock]
    let topic: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func view(for block: HelpBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text).font(.headline)
        case .signature(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding(.leading, 12)
                .padding(.top, -4)
        case .prose(let text, let level, let bullet):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if bullet { Text("•") }
                Text(HelpPanel.linked(text, topic: topic))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 14)
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize()
                    .padding(8)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
