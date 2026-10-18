// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The HTML page one math output is shown in.
public enum MathHTML {
    /// Font size of the math in CSS pixels.
    public static let mathSize = 19
    /// Space between the label column and the math: the editor's gutter
    /// spacing plus the text view's 5 pt line padding, so math lines up with input.
    public static let gap = 19

    /// A page holding `mathML` with an optional output label on the left.
    /// The page reports `[width, height, token]` to the `size` message
    /// handler; the token tells reports from this page apart from late
    /// reports of the page it replaced.
    public static func page(mathML: String, label: String?, token: Int = 0) -> String {
        // The label column is always there, so unlabelled math (questions) lines up too.
        let labelHTML = "<span class=\"lbl\">\(label.map { "(\(escape($0)))" } ?? "")</span>"
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; padding: 0; background: transparent; }
        body { font: 13px -apple-system, sans-serif; color: CanvasText; overflow-y: hidden; }
        .row { display: inline-flex; align-items: center; gap: \(gap)px; padding: 3px 6px 3px 0; }
        .lbl { font: 12px ui-monospace, Menlo, monospace; color: #8a8a8e; min-width: 52px;
               text-align: right; flex: none; }
        math { font-family: "STIX Two Math", math; font-size: \(mathSize)px; }
        mtext { font-family: "STIX Two Text", serif; }
        </style></head><body><div class="row">\(labelHTML)<div class="m">\(mathML)</div></div>
        <script>
        function report() {
          const r = document.querySelector('.row').getBoundingClientRect();
          window.webkit.messageHandlers.size.postMessage([Math.ceil(r.width), Math.ceil(r.height), \(token)]);
        }
        // Report once painted (two frames after fonts are ready), then on every resize.
        document.fonts.ready.then(() => requestAnimationFrame(() => requestAnimationFrame(report)));
        new ResizeObserver(report).observe(document.querySelector('.row'));
        </script></body></html>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}
