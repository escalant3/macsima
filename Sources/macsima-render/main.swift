// SPDX-License-Identifier: GPL-2.0-or-later
//
// Renders math outputs with the app's own web views.
//
//   macsima-render snapshots <out-dir>      PNGs of representative fixture outputs
//   macsima-render verify                   checks the shared renderer returns the right image,
//                                           and long math breaks into lines that fit
//   macsima-render wrap <out-dir> [width]   long outputs on one line and broken into lines (default 700)
//   macsima-render lab <page.html> <out.png>  snapshot of any HTML page (rendering experiments)
//   macsima-render bench <out-dir> [count] [images]
//       scroll and memory measurements (default 200 outputs); "images" uses
//       one shared web view rendering to images instead of one web view per output
//
// Run from the repository root (it reads Tests/Fixtures/transcripts/glue).

import AppKit
import MacsimaUI
import MaximaKit
import SwiftUI
import WebKit
import WXMLKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("macsima-render: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 1, ["snapshots", "bench", "lab", "verify", "wrap"].contains(args[0]) else {
    fail("usage: macsima-render snapshots|bench <out-dir> [count] | wrap <out-dir> [width] | lab <page.html> <out.png> | verify")
}
let outDir = URL(filePath: args.count > 1 ? args[1] : ".")
if args[0] != "lab" && args[0] != "verify" { try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }

/// Math chunks of one glue fixture, in order.
func chunks(_ name: String) -> [String] {
    let url = URL(filePath: "Tests/Fixtures/transcripts/glue/\(name).txt")
    guard let data = try? Data(contentsOf: url) else { fail("missing fixture \(url.path)") }
    var scanner = TagScanner()
    return (scanner.feed(data) + scanner.flush()).compactMap { if case .math(let m) = $0 { m } else { nil } }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

Task { @MainActor in
    switch args[0] {
    case "snapshots": await Snapshots.run(to: outDir)
    case "lab": await Lab.run(page: URL(filePath: args[1]), out: URL(filePath: args[2]))
    case "verify": await Verify.run()
    case "wrap": await Snapshots.lineBreaks(to: outDir, width: args.count > 2 ? Double(args[2]) ?? 700 : 700)
    default: await Bench.run(to: outDir, count: args.count > 2 ? Int(args[2]) ?? 200 : 200, images: args.contains("images"))
    }
    exit(0)
}
app.run()
