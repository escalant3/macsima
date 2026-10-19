// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WebKit

/// A WKWebView that shows one math output and reports its content size.
///
/// Vertical scroll-wheel events go to the enclosing scroll view: a web view
/// on macOS otherwise swallows them, and the worksheet stops scrolling while
/// the pointer is over math. Horizontal scrolling stays with the web view,
/// for outputs wider than the window.
public final class MathWKWebView: WKWebView {
    /// Web views alive right now, for the rendering measurements.
    @MainActor public static var liveCount = 0
    /// Web views created since launch.
    @MainActor public static var createdCount = 0

    var onSize: ((CGSize) -> Void)?
    /// Called with every size report, after `onSize` (tools and measurements).
    public var sizeObserver: ((CGSize) -> Void)?
    /// Number of web views that have reported a size at least once.
    @MainActor public static var sizedCount = 0
    private var hasSized = false
    /// The width the math of the last report takes on one line, before any
    /// line breaking.
    public private(set) var naturalWidth: CGFloat = 0
    /// Token of the page loaded last; size reports with another token are stale.
    private var pageToken = 0
    private var handler: SizeHandler?

    public init() {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let handler = SizeHandler()
        configuration.userContentController.add(handler, name: "size")
        super.init(frame: .zero, configuration: configuration)
        self.handler = handler
        handler.view = self
        setValue(false, forKey: "drawsBackground")
        underPageBackgroundColor = .clear
        MathWKWebView.liveCount += 1
        MathWKWebView.createdCount += 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    isolated deinit {
        MathWKWebView.liveCount -= 1
        configuration.userContentController.removeScriptMessageHandler(forName: "size")
    }

    public override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    public func show(mathML: String, label: String?, scale: CGFloat = 1, wrap: MathWrap = .none) {
        pageToken += 1
        loadHTMLString(MathHTML.page(mathML: mathML, label: label, token: pageToken, scale: scale, wrap: wrap),
                       baseURL: nil)
    }

    private final class SizeHandler: NSObject, WKScriptMessageHandler {
        weak var view: MathWKWebView?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let values = message.body as? [NSNumber], values.count == 4 else { return }
            let size = CGSize(width: values[0].doubleValue, height: values[1].doubleValue)
            MainActor.assumeIsolated {
                // A page that was replaced can still report (for example when the
                // view is resized for the next render); ignore it.
                guard let view, values[2].intValue == view.pageToken else { return }
                if !view.hasSized { view.hasSized = true; MathWKWebView.sizedCount += 1 }
                view.naturalWidth = values[3].doubleValue
                view.onSize?(size)
                view.sizeObserver?(size)
            }
        }
    }
}

/// SwiftUI wrapper: sizes itself to the math it shows.
struct MathWebView: NSViewRepresentable {
    let mathML: String
    let label: String?
    let scale: CGFloat
    let wrap: MathWrap
    @Binding var size: CGSize

    func makeNSView(context: Context) -> MathWKWebView {
        let view = MathWKWebView()
        view.onSize = { new in if new != size { size = new } }
        view.show(mathML: mathML, label: label, scale: scale, wrap: wrap)
        context.coordinator.shown = "\(scale)|" + mathML + (label ?? "")
        return view
    }

    func updateNSView(_ view: MathWKWebView, context: Context) {
        let key = "\(scale)|" + mathML + (label ?? "")
        if context.coordinator.shown != key {
            context.coordinator.shown = key
            view.show(mathML: mathML, label: label, scale: scale, wrap: wrap)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var shown = "" }
}

/// One math output: a web view sized to its content, breaking long math
/// into lines at its own width.
public struct MathOutputView: View {
    let mathML: String
    let label: String?
    /// False keeps the math on one line (a question's prompt).
    let wraps: Bool
    @Environment(\.worksheetScale) private var scale
    @State private var size = CGSize(width: 10, height: 28)

    public init(mathML: String, label: String?, wraps: Bool = true) {
        self.mathML = mathML
        self.label = label
        self.wraps = wraps
    }

    public var body: some View {
        MathWebView(mathML: mathML, label: label, scale: scale, wrap: wraps ? .page : .none, size: $size)
            .frame(height: size.height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A plot or other image output, with its label in the same gutter as math.
public struct ImageOutputView: View {
    let image: NSImage
    let label: String?

    public init(image: NSImage, label: String?) {
        self.image = image
        self.label = label
    }

    @Environment(\.worksheetScale) private var scale

    public var body: some View {
        let metrics = WorksheetMetrics(scale: scale)
        HStack(alignment: .center, spacing: metrics.mathGap) {
            Text(label.map { "(\($0))" } ?? "")
                .font(.system(size: metrics.gutterFontSize, design: .monospaced))
                .foregroundStyle(Color(white: 0.54))
                .frame(minWidth: metrics.gutterWidth, alignment: .trailing)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: min(image.size.width, 640) * scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
