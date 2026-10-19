// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MacsimaUI
import MaximaKit
import SwiftUI
import WebKit
import WXMLKit

@MainActor
enum Snapshots {
    /// (file name, fixture, chunk index) of the outputs to show.
    static let picks: [(String, String, Int)] = [
        ("01-integral-result", "01-integrate", 0),
        ("02-polynomial", "03-expand", 0),
        ("03-solve-roots", "09-solve", 0),
        ("04-matrix", "10-matrix", 0),
        ("05-sum-result", "12-sum", 0),
        ("06-taylor", "17-taylor", 0),
        ("07-greek-sqrt", "18-greek-sqrt", 0),
        ("08-asksign-atan", "07-asksign-integrate", 0),
        ("09-sum-noun", "31-display-forms", 0),
        ("10-product-noun", "31-display-forms", 1),
        ("11-integral-indefinite", "31-display-forms", 2),
        ("12-integral-definite", "31-display-forms", 3),
        ("13-limit", "31-display-forms", 4),
        ("14-limit-onesided", "31-display-forms", 5),
        ("15-derivative-mixed", "31-display-forms", 8),
        ("16-at", "31-display-forms", 9),
        ("17-box", "31-display-forms", 10),
        ("18-subscripts", "31-display-forms", 13),
        ("19-conjugate-abs", "31-display-forms", 14),
        ("20-matrix-fractions", "31-display-forms", 23),
        ("21-gaussian", "31-display-forms", 34),
        ("22-binomial-gamma", "31-display-forms", 42),
        ("23-long-expansion", "31-display-forms", 45),
    ]

    static func run(to dir: URL) async {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1000, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "macsima-render snapshots"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        for (file, fixture, index) in picks {
            let list = chunks(fixture)
            guard index < list.count else { print("skip \(file): no chunk \(index)"); continue }
            let out = MathMLTranslator.translate(list[index])
            await write(out, to: dir.appending(path: "\(file).png"), window: window, dark: false)
        }
        // Two in dark mode, to check the colors.
        for (file, fixture, index) in [("24-dark-matrix", "31-display-forms", 23), ("25-dark-integral", "31-display-forms", 3)] {
            await write(MathMLTranslator.translate(chunks(fixture)[index]), to: dir.appending(path: "\(file).png"),
                        window: window, dark: true)
        }
        await plot(to: dir.appending(path: "26-plot.png"))
        print("wrote snapshots to \(dir.path)")
    }

    /// Long outputs (fixture 33 and the expansion in 31) on one line, then
    /// broken into lines for a row `width` points wide (Phase 3, step 6).
    static func lineBreaks(to dir: URL, width: CGFloat) async {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1400, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "macsima-render wrap"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        let outs = (chunks("33-long-outputs") + [chunks("31-display-forms")[45]]).map(MathMLTranslator.translate)
        for (i, out) in outs.enumerated() {
            let name = String(format: "long-%02d", i + 1)
            await write(out, to: dir.appending(path: "\(name)-one-line.png"), window: window, dark: false)
            await write(out, to: dir.appending(path: "\(name)-\(Int(width)).png"), window: window, dark: false,
                        wrap: .width(width))
        }
        print("wrote line-break snapshots to \(dir.path)")
    }

    static func write(_ out: MathOutput, to file: URL, window: NSWindow, dark: Bool, wrap: MathWrap = .none) async {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let web = MathWKWebView()
        var frameWidth: CGFloat = 980
        if case .width(let w) = wrap {
            frameWidth = w + 40
            window.setContentSize(CGSize(width: w + 60, height: 400))
        }
        web.frame = NSRect(x: 0, y: 0, width: frameWidth, height: 300)
        window.contentView?.addSubview(web)
        defer { web.removeFromSuperview() }
        var latest = CGSize.zero
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var resumed = false
            web.sizeObserver = { size in
                latest = size
                if !resumed { resumed = true; c.resume() }
            }
            web.show(mathML: out.mathML, label: out.label, wrap: wrap)
        }
        try? await Task.sleep(for: .milliseconds(300))   // fonts settle, later size reports arrive
        let size = CGSize(width: latest.width + 8, height: latest.height + 8)
        web.frame.size = size
        try? await Task.sleep(for: .milliseconds(150))
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        guard let image = try? await web.takeSnapshot(configuration: config) else {
            print("snapshot failed: \(file.lastPathComponent)")
            return
        }
        save(image, background: dark ? NSColor(white: 0.12, alpha: 1) : .white, to: file)
        print("\(file.lastPathComponent): \(Int(size.width))x\(Int(size.height))")
    }

    /// A real wxplot2d through MaximaKit, shown as the app shows images.
    static func plot(to file: URL) async {
        let session = MaximaSession()
        do { try await session.start() } catch { print("plot skipped: \(error)"); return }
        var data: Data?
        var label = "%t1"
        if let stream = try? await session.evaluate(cellID: "plot", text: "wxplot2d(sin(x)*exp(-x/4), [x, 0, 4*%pi]);") {
            for await event in stream {
                if case .math(let xml) = event {
                    let out = MathMLTranslator.translate(xml)
                    if let path = out.imagePaths.first {
                        data = try? Data(contentsOf: URL(filePath: path))
                        label = out.label ?? label
                    }
                }
            }
        }
        await session.shutdown()
        guard let data, let image = NSImage(data: data) else { print("plot: no image"); return }
        let view = ImageOutputView(image: image, label: label).frame(width: 640).padding(8).background(.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            print("\(file.lastPathComponent): plot \(Int(image.size.width))x\(Int(image.size.height))")
        }
    }

    static func save(_ image: NSImage, background: NSColor, to file: URL) {
        let size = image.size
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}
