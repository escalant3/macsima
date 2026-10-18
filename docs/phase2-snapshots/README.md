# Phase 2 rendering snapshots

Made with `swift build && .build/debug/macsima-render snapshots docs/phase2-snapshots` from fixture outputs
(01-24, 24-25 in dark mode) and a live `wxplot2d` (26). Math is MathML from WXMLKit shown by WebKit with
STIX Two Math, captured with `WKWebView.takeSnapshot`; the plot row is a SwiftUI view.

`measurements/` holds the 200-output scroll benchmark (`macsima-render bench <dir> 200 [images]`), run
2026-10-18 on this Mac: one web view per output, and one shared web view rendering cached images.

`before-after-1.png` and `before-after-2.png` compare the first render with the one after the step 3b fixes for
WebKit's MathML layout, chosen by trying variants with `macsima-render lab <page.html> <out.png>`:

- fences (parens, list brackets, abs bars) around short content get `stretchy="false"`, because WebKit draws
  stretchy fences around short content raised above the baseline; around fractions, matrices, sums, integrals and
  limits they still stretch;
- every radical gets an invisible zero-width `(` strut, so `√a` clears the bar and adjacent roots share a height;
- conjugate is `<menclose notation="top">`; WebKit misplaces `mover` accents (U+00AF, U+203E, U+0305);
- `<p print="no">` (binomials) keeps its parens: in wxMaxima `print="no"` only affects text export.
