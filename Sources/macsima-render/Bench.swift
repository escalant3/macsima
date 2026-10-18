// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import Darwin
import MacsimaUI
import QuartzCore
import SwiftUI
import WXMLKit

/// Scrolls a worksheet-like list of `count` math outputs, one web view each
/// in a LazyVStack, and measures time to first render, scroll frame times
/// and memory.
@MainActor
enum Bench {
    struct Item: Identifiable {
        let id: Int
        let out: MathOutput
    }

    static func run(to dir: URL, count: Int, images: Bool) async {
        let pool = ["01-integrate", "03-expand", "09-solve", "10-matrix", "12-sum", "13-limit", "17-taylor",
                    "18-greek-sqrt", "31-display-forms"].flatMap(chunks).map(MathMLTranslator.translate)
            .filter { !$0.mathML.isEmpty }
        let items = (0..<count).map { i in
            var out = pool[i % pool.count]
            out.label = "%o\(i + 1)"
            return Item(id: i, out: out)
        }
        let webBefore = webContentProcesses()
        let footprintBefore = footprint()

        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 900, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = "macsima-render bench (\(count) outputs, \(images ? "images" : "web views"))"
        let root = ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    if images {
                        MathImageOutputView(mathML: item.out.mathML, label: item.out.label)
                    } else {
                        MathOutputView(mathML: item.out.mathML, label: item.out.label)
                    }
                }
            }
            .padding(12)
        }
        window.contentView = NSHostingView(rootView: root)
        let start = ContinuousClock.now
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // First screen: every web view created so far has reported its size
        // (image mode: the renderer has drawn what the first screen asked for).
        func firstScreenDone() -> Bool {
            if images { return MathSnapshotRenderer.shared.renderCount >= 14 }
            return MathWKWebView.createdCount > 0 && MathWKWebView.sizedCount >= MathWKWebView.createdCount
        }
        while !firstScreenDone() {
            try? await Task.sleep(for: .milliseconds(5))
            if ContinuousClock.now - start > .seconds(30) { break }
        }
        let firstScreen = ContinuousClock.now - start
        let firstScreenViews = MathWKWebView.createdCount

        guard let scrollView = findScrollView(in: window.contentView!) else { fail("no scroll view") }
        let scroller = Scroller(scrollView: scrollView, step: 24)
        let down = await scroller.scrollToEnd()
        try? await Task.sleep(for: .seconds(2))   // let late web views finish
        let createdAfterDown = MathWKWebView.createdCount
        let liveAfterDown = MathWKWebView.liveCount
        let up = await Scroller(scrollView: scrollView, step: -24).scrollToEnd()
        try? await Task.sleep(for: .seconds(2))

        let webAfter = webContentProcesses()
        let newWeb = webAfter.filter { webBefore[$0.key] == nil }
        let report: [String: Any] = [
            "outputs": count,
            "mode": images ? "images from one shared web view" : "one web view per output",
            "imagesRendered": MathSnapshotRenderer.shared.renderCount,
            "firstScreenMs": ms(firstScreen),
            "firstScreenWebViews": firstScreenViews,
            "scrollDown": down.summary,
            "scrollUp": up.summary,
            "webViewsCreated": createdAfterDown,
            "webViewsAliveAfterScroll": liveAfterDown,
            "webViewsAliveAtEnd": MathWKWebView.liveCount,
            "appFootprintMB": mb(footprint() - footprintBefore),
            "appFootprintTotalMB": mb(footprint()),
            "webContentProcesses": newWeb.count,
            "webContentRSSMB": mb(UInt64(newWeb.values.reduce(0, +)) * 1024),
            "documentHeight": Int(scrollView.documentView?.frame.height ?? 0),
        ]
        let json = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try? json.write(to: dir.appending(path: "bench-\(count)-\(images ? "images" : "webviews").json"))
        print(String(decoding: json, as: UTF8.self))
    }

    static func ms(_ d: Duration) -> Int {
        Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }

    static func mb(_ bytes: UInt64) -> Double { (Double(bytes) / 1_048_576 * 10).rounded() / 10 }

    static func findScrollView(in view: NSView) -> NSScrollView? {
        if let s = view as? NSScrollView { return s }
        for sub in view.subviews { if let s = findScrollView(in: sub) { return s } }
        return nil
    }

    /// This process's physical footprint.
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// pid → RSS in KB of every WebKit WebContent process.
    static func webContentProcesses() -> [Int32: Int] {
        let p = Process()
        p.executableURL = URL(filePath: "/bin/ps")
        p.arguments = ["-axo", "pid=,rss=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        var result: [Int32: Int] = [:]
        for line in String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, parts[2].contains("com.apple.WebKit.WebContent"),
                  let pid = Int32(parts[0]), let rss = Int(parts[1]) else { continue }
            result[pid] = rss
        }
        return result
    }
}

/// Scrolls one step per display frame and records frame intervals.
@MainActor
final class Scroller: NSObject {
    struct Result {
        var frames = 0
        var hitches = 0
        var worstMs = 0.0
        var totalMs = 0.0
        var targetMs = 0.0
        var summary: [String: Any] {
            ["frames": frames, "hitches": hitches, "worstFrameMs": (worstMs * 10).rounded() / 10,
             "totalMs": Int(totalMs), "targetFrameMs": (targetMs * 10).rounded() / 10]
        }
    }

    let scrollView: NSScrollView
    let step: CGFloat
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var result = Result()
    private var done: CheckedContinuation<Result, Never>?
    private var started: CFTimeInterval = 0

    init(scrollView: NSScrollView, step: CGFloat) {
        self.scrollView = scrollView
        self.step = step
    }

    func scrollToEnd() async -> Result {
        await withCheckedContinuation { c in
            done = c
            let link = scrollView.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let target = (link.targetTimestamp - link.timestamp) * 1000
        if last > 0 {
            let interval = (now - last) * 1000
            result.frames += 1
            result.worstMs = max(result.worstMs, interval)
            if interval > target * 1.5 { result.hitches += 1 }
            result.targetMs = target
        } else {
            started = now
        }
        last = now
        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        var origin = clip.bounds.origin
        origin.y = min(max(0, origin.y + step), maxY)
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        let atEnd = step > 0 ? origin.y >= maxY - 0.5 : origin.y <= 0.5
        if atEnd && result.frames > 5 {
            result.totalMs = (now - started) * 1000
            link.invalidate()
            self.link = nil
            done?.resume(returning: result)
            done = nil
        }
    }
}
