// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// How a math page breaks math wider than its row into lines.
public enum MathWrap: Hashable, Sendable {
    /// Never: the math stays on one line however wide.
    case none
    /// To a row this many points wide, label column included.
    case width(CGFloat)
    /// To the page's own width, again whenever it changes (live views).
    case page

    var script: String {
        switch self {
        case .none: "0"
        case .width(let w): String(format: "%.1f", w)
        case .page: "-1"
        }
    }
}

/// The HTML page one math output is shown in.
public enum MathHTML {
    /// Font size of the math in CSS pixels.
    public static let mathSize = 19
    /// Space between the label column and the math: the editor's gutter
    /// spacing plus the text view's 5 pt line padding, so math lines up with input.
    public static let gap = 19
    /// The editor's gutter spacing, the part of `gap` that zooms.
    static let gutterSpacing = 14
    /// Width of the label column, the editor's gutter width.
    static let labelWidth = 52

    /// A page holding `mathML` with an optional output label on the left.
    /// The page reports `[width, height, token, width on one line]` to the
    /// `size` message handler; the token tells reports from this page apart
    /// from late reports of the page it replaced.
    /// `scale` is the worksheet's zoom (1 = 100%): fonts, the label column
    /// and the gap grow with it, except the text view's fixed 5 pt line
    /// padding, which is part of the gap. `wrap` says where long math
    /// breaks into lines (MathLineBreaking).
    /// `labelColumn` false leaves out the label column (a copied picture).
    public static func page(mathML: String, label: String?, token: Int = 0, scale: CGFloat = 1,
                            wrap: MathWrap = .none, labelColumn: Bool = true) -> String {
        func px(_ v: CGFloat) -> String { String(format: "%.2fpx", v * scale) }
        let gap = String(format: "%.2fpx", CGFloat(gutterSpacing) * scale + CGFloat(Self.gap - gutterSpacing))
        // The label column is always there, so unlabelled math (questions) lines up too.
        let labelHTML = labelColumn ? "<span class=\"lbl\">\(label.map { "(\(escape($0)))" } ?? "")</span>"
            : "<span class=\"lbl\" style=\"display: none\"></span>"
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; padding: 0; background: transparent; }
        body { font: \(px(13)) -apple-system, sans-serif; color: CanvasText; overflow-y: hidden; }
        .row { display: inline-flex; align-items: center; gap: \(gap); padding: \(px(3)) \(px(6)) \(px(3)) 0; }
        .lbl { font: \(px(12)) ui-monospace, Menlo, monospace; color: #8a8a8e; min-width: \(px(CGFloat(labelWidth)));
               text-align: right; flex: none; }
        math { font-family: "STIX Two Math", math; font-size: \(px(CGFloat(mathSize))); }
        mtext { font-family: "STIX Two Text", serif; }
        .row.wrapped { align-items: baseline; }
        .m.wrapped { display: flex; flex-wrap: wrap; align-items: baseline; row-gap: \(px(7)); }
        .w { display: inline-flex; align-items: baseline; flex: none; }
        </style></head><body><div class="row">\(labelHTML)<div class="m">\(mathML)</div></div>
        <script>
        \(MathLineBreaking.script)
        const wrap = \(wrap.script);
        let ready = false, laidOutFor = null, natural = 0;
        function report() {
          if (!ready) return;
          const width = wrap < 0 ? document.documentElement.clientWidth : wrap;
          if (width !== laidOutFor) { natural = layoutMath(width); laidOutFor = width; }
          const [w, h] = measureMath();
          window.webkit.messageHandlers.size.postMessage([w, h, \(token), natural]);
        }
        // Lay out and report once painted (two frames after fonts are ready),
        // then on every resize.
        document.fonts.ready.then(() => requestAnimationFrame(() => requestAnimationFrame(() => { ready = true; report(); })));
        const observer = new ResizeObserver(report);
        observer.observe(document.querySelector('.row'));
        if (wrap < 0) observer.observe(document.documentElement);
        </script></body></html>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}
