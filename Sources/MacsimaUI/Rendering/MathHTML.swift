// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The HTML page one math output is shown in.
public enum MathHTML {
    /// Font size of the math in CSS pixels.
    public static let mathSize = 19

    /// A page holding `mathML` with an optional output label on the left.
    /// The page reports its content size to the `size` message handler.
    public static func page(mathML: String, label: String?) -> String {
        let labelHTML = label.map { "<span class=\"lbl\">(\(escape($0)))</span>" } ?? ""
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; padding: 0; background: transparent; }
        body { font: 13px -apple-system, sans-serif; color: CanvasText; overflow-y: hidden; }
        .row { display: inline-flex; align-items: center; gap: 14px; padding: 3px 6px 3px 0; }
        .lbl { font: 12px ui-monospace, Menlo, monospace; color: #8a8a8e; min-width: 52px;
               text-align: right; flex: none; }
        math { font-family: "STIX Two Math", math; font-size: \(mathSize)px; }
        mtext { font-family: "STIX Two Text", serif; }
        </style></head><body><div class="row">\(labelHTML)<div class="m">\(mathML)</div></div>
        <script>
        function report() {
          const r = document.querySelector('.row').getBoundingClientRect();
          window.webkit.messageHandlers.size.postMessage([Math.ceil(r.width), Math.ceil(r.height)]);
        }
        window.addEventListener('load', report);
        document.fonts.ready.then(report);
        new ResizeObserver(report).observe(document.querySelector('.row'));
        </script></body></html>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}
