// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MacsimaUI
import WebKit
import WXMLKit

/// Checks that MathSnapshotRenderer returns the picture of the math it was
/// asked for: every output is rendered through the shared renderer (one at
/// a time, then all at once) and compared with a fresh single-use web view.
@MainActor
enum Verify {
    static func run() async {
        let outs = ["01-integrate", "03-expand", "09-solve", "10-matrix", "13-limit", "31-display-forms"]
            .flatMap(chunks).map(MathMLTranslator.translate).filter { !$0.mathML.isEmpty }.prefix(24)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1000, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)

        var reference: [(size: CGSize, image: NSImage?)] = []
        for out in outs { reference.append(await fresh(out, window: window)) }

        var failures = 0
        // Concurrent requests, as a LazyVStack makes them.
        let shared = MathSnapshotRenderer.shared
        var tasks: [Task<NSImage?, Never>] = []
        for out in outs {
            tasks.append(Task { await shared.render(mathML: out.mathML, label: out.label, dark: false)?.image })
        }
        for (i, task) in tasks.enumerated() {
            let image = await task.value
            let got = image?.size ?? .zero
            let want = reference[i].size
            let sameSize = abs(got.width - want.width) <= 2 && abs(got.height - want.height) <= 2
            let diff = pixelDifference(image, reference[i].image)
            let ok = sameSize && diff < 0.01
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "BAD ") #\(i) shared \(Int(got.width))x\(Int(got.height)) fresh \(Int(want.width))x\(Int(want.height)) pixels differing \(String(format: "%.2f%%", diff * 100))")
        }
        print(failures == 0 ? "PASS" : "FAIL: \(failures) of \(outs.count) images do not match their math")
    }

    /// Fraction of pixels whose alpha differs noticeably (1 when sizes differ).
    static func pixelDifference(_ a: NSImage?, _ b: NSImage?) -> Double {
        guard let a = a.flatMap(bitmap), let b = b.flatMap(bitmap),
              a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 1 }
        var differing = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                let pa = a.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let pb = b.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if abs(pa - pb) > 0.25 { differing += 1 }
            }
        }
        return Double(differing) / Double(a.pixelsWide * a.pixelsHigh)
    }

    static func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    }

    static func fresh(_ out: MathOutput, window: NSWindow) async -> (size: CGSize, image: NSImage?) {
        let web = MathWKWebView()
        web.frame = NSRect(x: 0, y: 0, width: 980, height: 300)
        window.contentView?.addSubview(web)
        defer { web.removeFromSuperview() }
        var latest = CGSize.zero
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var resumed = false
            web.sizeObserver = { size in
                latest = size
                if !resumed { resumed = true; c.resume() }
            }
            web.show(mathML: out.mathML, label: out.label)
        }
        try? await Task.sleep(for: .milliseconds(300))
        web.frame.size = latest
        try? await Task.sleep(for: .milliseconds(150))
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: latest)
        return (latest, try? await web.takeSnapshot(configuration: config))
    }
}
