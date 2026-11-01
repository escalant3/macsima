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
        let wrapFailures = await lineBreaks(window: window)
        print(wrapFailures == 0 ? "PASS line breaks" : "FAIL: \(wrapFailures) line-break checks")
        let partFailures = await parts()
        print(partFailures == 0 ? "PASS parts" : "FAIL: \(partFailures) outputs with misplaced parts")
    }

    /// Where the renderer says each part was drawn (selecting inside math):
    /// every name, number and operator has a rectangle inside the image, a
    /// click on it selects it, and parts lie inside the part holding them.
    /// The long outputs are broken at 480 points, so parts split over lines.
    static func parts() async -> Int {
        let outs = ["01-integrate", "03-expand", "09-solve", "10-matrix", "13-limit", "31-display-forms", "33-long-outputs"]
            .flatMap(chunks).map(MathMLTranslator.translate).filter { !$0.mathML.isEmpty }
        var failures = 0
        for (i, out) in outs.enumerated() {
            guard let tree = out.tree,
                  let rendered = await MathSnapshotRenderer.shared.render(mathML: out.taggedMathML, label: out.label,
                                                                          dark: false, width: 480)
            else { failures += 1; print("BAD part #\(i): not rendered"); continue }
            let layout = MathLayout(tree: tree, measured: rendered.parts)
            if ProcessInfo.processInfo.environment["MACSIMA_PARTS_DEBUG"] == String(i) {
                print(out.taggedMathML)
                for id in tree.nodes.indices {
                    print(id, tree.parent[id], tree.nodes[id].name ?? "", tree.nodes[id].textContent.prefix(20),
                          rendered.parts[id].map { "own \($0)" } ?? "", layout.rects[id])
                }
            }
            let image = CGRect(origin: .zero, size: rendered.size).insetBy(dx: -1, dy: -1)
            var problems: [String] = []
            let leaves = tree.nodes.indices.filter {
                ["mi", "mn", "mo", "v", "n"].contains(tree.nodes[$0].name ?? "")
                    && !tree.nodes[$0].textContent.trimmingCharacters(in: .whitespaces).isEmpty
                    && out.taggedMathML.contains("data-p=\"\($0)\"")
            }
            for id in leaves {
                guard let first = layout.rects[id].first else { problems.append("no box for #\(id)"); continue }
                if !layout.rects[id].allSatisfy({ image.contains($0) }) { problems.append("#\(id) outside the image") }
                let center = CGRect(x: first.midX, y: first.midY, width: 1, height: 1)
                if layout.select(center) != .node(id) { problems.append("a click on #\(id) selects \(String(describing: layout.select(center)))") }
            }
            // As drawn, without the padding that makes thin parts easier to click.
            let drawn = MathLayout(tree: tree, measured: rendered.parts, minimumSize: 0)
            for id in tree.nodes.indices where !rendered.parts[id, default: []].isEmpty {
                let p = tree.parent[id]
                guard p >= 0, !rendered.parts[p, default: []].isEmpty else { continue }
                let holder = drawn.rects[p].map { $0.insetBy(dx: -2, dy: -2) }
                if !drawn.rects[id].allSatisfy({ r in holder.contains { $0.contains(r) } }) {
                    problems.append("#\(id) outside its parent #\(p)")
                }
            }
            if !problems.isEmpty { failures += 1 }
            print("\(problems.isEmpty ? "ok  " : "BAD ") part #\(i): \(leaves.count) parts, \(Int(rendered.size.width))x\(Int(rendered.size.height))"
                  + (problems.isEmpty ? "" : " — " + problems.prefix(4).joined(separator: "; ")))
        }
        return failures
    }

    /// The long outputs (fixture 33 and the expansion in 31), laid out at
    /// several widths: math wider than its row breaks into lines that fit,
    /// keeping every symbol in order. The matrix can't break and must not.
    static func lineBreaks(window: NSWindow) async -> Int {
        let outs = (chunks("33-long-outputs") + [chunks("31-display-forms")[45]]).map(MathMLTranslator.translate)
        var failures = 0
        for (i, out) in outs.enumerated() {
            for width in [480.0, 700, 1000] {
                let web = MathWKWebView()
                web.frame = NSRect(x: 0, y: 0, width: width + 40, height: 300)
                window.contentView?.addSubview(web)
                var latest = CGSize.zero
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    var resumed = false
                    web.sizeObserver = { size in
                        latest = size
                        if !resumed { resumed = true; c.resume() }
                    }
                    web.show(mathML: out.mathML, label: out.label, wrap: .width(width))
                }
                let report = try? await web.evaluateJavaScript("lineBreakReport()") as? [Any]
                web.removeFromSuperview()
                let lines = report?[0] as? Int ?? 0
                let kept = report?[1] as? String ?? "", given = report?[2] as? String ?? "?"
                let natural = web.naturalWidth
                let isMatrix = out.mathML.contains("<mtable>")
                var problems: [String] = []
                if natural > width {
                    if isMatrix {
                        if lines > 1 { problems.append("a matrix broke") }
                    } else {
                        if latest.width > width { problems.append("wider than its row") }
                        if lines < 2 { problems.append("not broken") }
                    }
                } else if lines > 1 {
                    problems.append("broken though it fits")
                }
                if lines > 1 && kept != given { problems.append("text changed") }
                if !problems.isEmpty { failures += 1 }
                print("\(problems.isEmpty ? "ok  " : "BAD ") long #\(i) at \(Int(width)): \(lines) line(s), \(Int(latest.width))x\(Int(latest.height)), one line \(Int(natural))"
                      + (problems.isEmpty ? "" : " — " + problems.joined(separator: ", ")))
            }
        }
        // A live view breaks at its own width, and again when resized.
        let web = MathWKWebView()
        web.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
        window.contentView?.addSubview(web)
        defer { web.removeFromSuperview() }
        var sizes: [CGSize] = []
        web.sizeObserver = { sizes.append($0) }
        web.show(mathML: outs[0].mathML, label: outs[0].label, wrap: .page)
        for _ in 0..<50 where sizes.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        let narrow = sizes.last ?? .zero
        web.frame.size.width = 1000
        for _ in 0..<50 where sizes.last == narrow { try? await Task.sleep(for: .milliseconds(100)) }
        let wide = sizes.last ?? .zero
        let liveOK = narrow.width > 0 && narrow.width <= 700 && wide.width > 700 && wide.width <= 1000 && wide.height < narrow.height
        if !liveOK { failures += 1 }
        print("\(liveOK ? "ok  " : "BAD ") live view: \(Int(narrow.width))x\(Int(narrow.height)) at 700, \(Int(wide.width))x\(Int(wide.height)) at 1000")
        return failures
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
