# Phase 2 rendering snapshots

Made with `swift build && .build/debug/macsima-render snapshots docs/phase2-snapshots` from fixture outputs
(01-24, 24-25 in dark mode) and a live `wxplot2d` (26). Math is MathML from WXMLKit shown by WebKit with
STIX Two Math, captured with `WKWebView.takeSnapshot`; the plot row is a SwiftUI view.

`measurements/` holds the 200-output scroll benchmark (`macsima-render bench <dir> 200 [images]`), run
2026-10-18 on this Mac: one web view per output, and one shared web view rendering cached images.
