// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WebKit

/// Renders math to images with one shared, hidden web view, so a worksheet
/// needs one WebKit content process instead of one per output. Results are
/// cached by content and appearance. Requests run one at a time.
@MainActor
public final class MathSnapshotRenderer {
    public static let shared = MathSnapshotRenderer()

    public struct Rendered {
        public let image: NSImage
        /// Size in points.
        public let size: CGSize
    }

    private let window: NSWindow
    private let web: MathWKWebView
    private var cache: [String: Rendered] = [:]
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Renders done since launch (measurements).
    public private(set) var renderCount = 0

    private init() {
        // Kept on screen but fully transparent and behind everything: WebKit
        // stops painting views in windows that are off screen or ordered out.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 400),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        web = MathWKWebView()
        web.frame = NSRect(x: 0, y: 0, width: 1200, height: 400)
        window.contentView = NSView(frame: web.frame)
        window.contentView?.addSubview(web)
        window.orderBack(nil)
    }

    public func cached(mathML: String, label: String?, dark: Bool) -> Rendered? {
        cache[Self.key(mathML, label, dark)]
    }

    public func render(mathML: String, label: String?, dark: Bool) async -> Rendered? {
        let key = Self.key(mathML, label, dark)
        if let hit = cache[key] { return hit }
        while busy { await withCheckedContinuation { waiting.append($0) } }
        if let hit = cache[key] { wakeNext(); return hit }
        busy = true
        defer { busy = false; wakeNext() }

        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        web.frame.size = CGSize(width: 1200, height: 400)
        var latest = CGSize.zero
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var resumed = false
            web.sizeObserver = { size in
                latest = size
                if !resumed { resumed = true; c.resume() }
            }
            web.show(mathML: mathML, label: label)
        }
        let size = CGSize(width: max(1, latest.width), height: max(1, latest.height))
        web.frame.size = size
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        guard let image = try? await web.takeSnapshot(configuration: config) else { return nil }
        let rendered = Rendered(image: image, size: size)
        cache[key] = rendered
        renderCount += 1
        return rendered
    }

    private func wakeNext() {
        if !waiting.isEmpty { waiting.removeFirst().resume() }
    }

    private static func key(_ mathML: String, _ label: String?, _ dark: Bool) -> String {
        "\(dark ? "d" : "l")|\(label ?? "")|\(mathML)"
    }
}

/// One math output shown as an image from `MathSnapshotRenderer`.
public struct MathImageOutputView: View {
    let mathML: String
    let label: String?
    @Environment(\.colorScheme) private var scheme
    @State private var rendered: MathSnapshotRenderer.Rendered?

    public init(mathML: String, label: String?) {
        self.mathML = mathML
        self.label = label
    }

    public var body: some View {
        Group {
            if let rendered {
                Image(nsImage: rendered.image)
                    .frame(width: rendered.size.width, height: rendered.size.height)
            } else {
                Color.clear.frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(scheme)|\(label ?? "")|\(mathML)") {
            let dark = scheme == .dark
            rendered = MathSnapshotRenderer.shared.cached(mathML: mathML, label: label, dark: dark)
            if rendered == nil {
                rendered = await MathSnapshotRenderer.shared.render(mathML: mathML, label: label, dark: dark)
            }
        }
    }
}
