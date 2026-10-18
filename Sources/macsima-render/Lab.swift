// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import WebKit

/// Loads an HTML file in a plain WKWebView and saves a snapshot of the whole
/// page, for comparing MathML variants.
@MainActor
enum Lab {
    final class Loader: NSObject, WKNavigationDelegate {
        var done: CheckedContinuation<Void, Never>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            done?.resume()
            done = nil
        }
    }

    static func run(page: URL, out: URL) async {
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 1100, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900))
        window.contentView = web
        let loader = Loader()
        web.navigationDelegate = loader
        await withCheckedContinuation { c in
            loader.done = c
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        try? await Task.sleep(for: .milliseconds(500))
        let height = (try? await web.evaluateJavaScript("document.body.scrollHeight") as? Double) ?? 900
        web.frame.size.height = height
        window.setContentSize(NSSize(width: 1100, height: height))
        try? await Task.sleep(for: .milliseconds(300))
        guard let image = try? await web.takeSnapshot(configuration: nil),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { fail("snapshot failed") }
        try? png.write(to: out)
        print("wrote \(out.path)")
    }
}
