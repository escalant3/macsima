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
    /// The width each math takes on one line, keyed like `cache` without the
    /// wrap width: math narrower than a row needs no render of its own per width.
    private var naturalWidths: [String: CGFloat] = [:]
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Renders done since launch (measurements).
    public private(set) var renderCount = 0
    /// The latest renders, for checks: label, width broken at (nil: none), size.
    public private(set) var recent: [(label: String?, wrap: CGFloat?, size: CGSize)] = []
    /// Renders given up after `timeout` without an answer from the page.
    public private(set) var timeouts = 0
    static let timeout = Duration.seconds(10)

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

    public func cached(mathML: String, label: String?, dark: Bool, scale: CGFloat = 1, width: CGFloat? = nil) -> Rendered? {
        cache[Self.key(mathML, label, dark, scale, effectiveWidth(width, mathML, label, dark, scale))]
    }

    /// `scale` is the worksheet's zoom: the math is laid out again at that
    /// size, so zoomed math stays sharp. Math wider than `width` (points,
    /// label column included) is broken into lines; nil never breaks.
    /// `labelColumn` false renders the math alone, for copying (not cached).
    public func render(mathML: String, label: String?, dark: Bool, scale: CGFloat = 1,
                       width: CGFloat? = nil, labelColumn: Bool = true) async -> Rendered? {
        var wrap = effectiveWidth(width, mathML, label, dark, scale)
        var key = Self.key(mathML, label, dark, scale, wrap) + (labelColumn ? "" : "|bare")
        if let hit = cache[key] { return hit }
        while busy { await withCheckedContinuation { waiting.append($0) } }
        // Another render may have found the math's width meanwhile.
        wrap = effectiveWidth(width, mathML, label, dark, scale)
        key = Self.key(mathML, label, dark, scale, wrap) + (labelColumn ? "" : "|bare")
        if let hit = cache[key] { wakeNext(); return hit }
        busy = true
        defer { busy = false; wakeNext() }

        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let frameWidth = max(1200, (wrap ?? 0) + 40)
        window.setContentSize(CGSize(width: frameWidth, height: 400))
        web.frame.size = CGSize(width: frameWidth, height: 400)
        var latest = CGSize.zero
        var timedOut = false
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var resumed = false
            web.sizeObserver = { size in
                latest = size
                if !resumed { resumed = true; c.resume() }
            }
            web.show(mathML: mathML, label: label, scale: scale, wrap: wrap.map { .width($0) } ?? .none,
                     labelColumn: labelColumn)
            // A page that never reports its size would keep the renderer
            // busy, and every later output in the app would wait behind it.
            Task { @MainActor in
                try? await Task.sleep(for: Self.timeout)
                if !resumed { resumed = true; timedOut = true; c.resume() }
            }
        }
        if timedOut {
            web.sizeObserver = nil
            timeouts += 1
            return nil
        }
        let natural = web.naturalWidth
        if labelColumn { naturalWidths[Self.key(mathML, label, dark, scale, nil)] = natural }
        let size = CGSize(width: max(1, latest.width), height: max(1, latest.height))
        web.frame.size = size
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        guard let image = try? await web.takeSnapshot(configuration: config) else { return nil }
        let rendered = Rendered(image: image, size: size)
        cache[key] = rendered
        // Math that fitted is the same picture at any width.
        if labelColumn, let wrap, natural <= wrap { cache[Self.key(mathML, label, dark, scale, nil)] = rendered }
        renderCount += 1
        recent.append((label, wrap, size))
        if recent.count > 100 { recent.removeFirst() }
        return rendered
    }

    /// The width to break at: nil when the math is known to fit.
    private func effectiveWidth(_ width: CGFloat?, _ mathML: String, _ label: String?, _ dark: Bool,
                                _ scale: CGFloat) -> CGFloat? {
        guard let width else { return nil }
        if let natural = naturalWidths[Self.key(mathML, label, dark, scale, nil)], natural <= width.rounded(.down) {
            return nil
        }
        return width.rounded(.down)
    }

    private func wakeNext() {
        if !waiting.isEmpty { waiting.removeFirst().resume() }
    }

    private static func key(_ mathML: String, _ label: String?, _ dark: Bool, _ scale: CGFloat,
                            _ width: CGFloat?) -> String {
        "\(dark ? "d" : "l")|\(scale)|\(width.map { "\(Int($0))" } ?? "-")|\(label ?? "")|\(mathML)"
    }
}

/// One math output shown as an image from `MathSnapshotRenderer`, broken
/// into lines to fit the width it gets. Math that can't break (a wide
/// matrix) scrolls sideways.
public struct MathImageOutputView: View {
    let mathML: String
    let label: String?
    /// False keeps the math on one line (a question's prompt, sized to fit).
    let wraps: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.worksheetScale) private var scale
    @State private var rendered: MathSnapshotRenderer.Rendered?
    @State private var width: CGFloat = 0

    public init(mathML: String, label: String?, wraps: Bool = true) {
        self.mathML = mathML
        self.label = label
        self.wraps = wraps
    }

    public var body: some View {
        Group {
            if let rendered, wraps, rendered.size.width > width + 1, width > 0 {
                ScrollView(.horizontal) { image(rendered) }
                    .scrollIndicators(.automatic)
            } else if let rendered {
                image(rendered)
            } else {
                Color.clear.frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded(.down) } action: { width = $0 }
        .task(id: "\(scheme)|\(scale)|\(wraps ? width : -1)|\(label ?? "")|\(mathML)") {
            guard width > 0 || !wraps else { return }
            let width: CGFloat? = wraps ? width : nil
            let dark = scheme == .dark
            let renderer = MathSnapshotRenderer.shared
            // Keep showing the old image until the new one is ready.
            if let hit = renderer.cached(mathML: mathML, label: label, dark: dark, scale: scale, width: width) {
                rendered = hit
                return
            }
            // While the window is being resized, wait for the width to settle.
            if rendered != nil {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            if let new = await renderer.render(mathML: mathML, label: label, dark: dark, scale: scale, width: width) {
                rendered = new
            }
        }
    }

    private func image(_ rendered: MathSnapshotRenderer.Rendered) -> some View {
        Image(nsImage: rendered.image)
            .frame(width: rendered.size.width, height: rendered.size.height)
    }
}
