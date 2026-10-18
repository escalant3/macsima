// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import WorksheetKit

/// A worksheet with every cell and output kind, for screenshots and layout
/// checks. A new document starts with it when the app is launched with
/// `-MacsimaDemoWorksheet YES`. The math XML is copied from the fixtures.
enum DemoWorksheet {
    static var requested: Bool { UserDefaults.standard.bool(forKey: "MacsimaDemoWorksheet") }

    static func make() -> Worksheet {
        Worksheet(cells: [
            Cell(kind: .title, input: "Macsima demo"),
            Cell(kind: .section, input: "Calculus"),
            Cell(kind: .text, input: "An integral, a limit and a derivative, as Maxima prints them."),
            Cell(kind: .code, input: "integrate(sin(x), x);", outputs: [
                .math(xml: #"<math><lbl altCopy="%o1">(%o1) </lbl><mo>-</mo><fn lisp="wxxml-function"><fnm lisp="wxxml-function">cos</fnm><mrow><p><mrow><mi lisp="*var-tag*">x</mi></mrow></p></mrow></fn></math>"#),
            ], inputLabel: 1),
            Cell(kind: .code, input: "'limit(sin(x)/x, x, 0);", outputs: [
                .math(xml: #"<math><lbl altCopy="%o2">(%o2) </lbl><lm><fnm>lim</fnm><mrow><mi lisp="*var-tag*">x</mi><mo>-></mo><mn>0</mn></mrow><mrow><mfrac lisp="wxxml-mquotient"><mrow><fn lisp="wxxml-function"><fnm lisp="wxxml-function">sin</fnm><mrow><p><mrow><mi lisp="*var-tag*">x</mi></mrow></p></mrow></fn></mrow><mrow><mi lisp="*var-tag*">x</mi></mrow></mfrac></mrow></lm></math>"#),
            ], inputLabel: 2),
            Cell(kind: .subsection, input: "Errors and questions"),
            Cell(kind: .code, input: "1/0;", outputs: [
                .text("expt: undefined: 0 to a negative exponent."),
                .error(kind: "maxima", message: "expt: undefined: 0 to a negative exponent."),
            ], inputLabel: 3),
            Cell(kind: .code, input: "asksign(y);", outputs: [
                .question(prompt: #"<math><st>Is </st><mi lisp="*var-tag*">y</mi><st> positive, negative or zero?</st></math>"#, answer: "pos;"),
                .math(xml: #"<math><lbl altCopy="%o4">(%o4) </lbl><mi lisp="*var-tag*">pos</mi></math>"#),
            ], inputLabel: 4),
            Cell(kind: .code, input: "print(\"hello\")$ display2d:false$ (x+1)^2/y;", outputs: [
                .text("hello "),
                .text("(%o7) (x+1)^2/y"),
            ], inputLabel: 5),
            Cell(kind: .code),
        ])
    }
}
