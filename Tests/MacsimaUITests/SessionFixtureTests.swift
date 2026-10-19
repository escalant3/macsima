// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WorksheetKit
@testable import MacsimaUI

/// Ten small sessions evaluated by the real Maxima through the same
/// controller the window uses, saved as Tests/Fixtures/wxmx/macsima-written.
/// Record them with MACSIMA_RECORD_WXMX=1. Every run reopens each file,
/// re-evaluates it in a fresh Maxima and requires the same outputs (the
/// Phase 2 exit check), and requires that saving again gives the same
/// content.xml.
@MainActor
@Suite(.serialized, .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/maxima")))
struct SessionFixtureTests {
    static let dir = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/wxmx/macsima-written")
    static let recording = ProcessInfo.processInfo.environment["MACSIMA_RECORD_WXMX"] == "1"

    nonisolated static func code(_ s: String) -> Cell { Cell(kind: .code, input: s) }

    /// name → cells and the answers to give, in order.
    nonisolated static let sessions: [String: (cells: [Cell], answers: [String])] = [
        "01-cell-kinds": ([
            Cell(kind: .title, input: "Cell kinds"), Cell(kind: .section, input: "A section"),
            Cell(kind: .subsection, input: "A subsection"), Cell(kind: .subsubsection, input: "A subsubsection"),
            Cell(kind: .text, input: "A text cell.\nIt has two lines."), code("2+2;"),
        ], []),
        "02-plots": ([
            Cell(kind: .title, input: "Plots"), code("wxplot2d(sin(x), [x, 0, %pi]);"),
            code("wxplot2d([x^2, x^3], [x, -1, 1]);"),
        ], []),
        "03-errors": ([
            Cell(kind: .section, input: "Errors"), code("1/0;"), code("x+;"), code("error(\"custom failure\");"),
            code("?car(1);"), code("error(\"value is\", x^2);"), code("2+2;"),
        ], []),
        "04-question": ([
            Cell(kind: .text, input: "A question answered inline."), code("asksign(y);"),
            code("integrate(1/(x^2+k), x);"),
        ], ["pos", "positive"]),
        "05-long-output": ([
            code("expand((x+y)^30);"), code("100!;"), code("makelist(i^2, i, 1, 60);"),
        ], []),
        "06-display-forms": ([
            code("'integrate(f(x), x, 0, 1);"), code("'sum(1/k^2, k, 1, inf);"), code("'limit(sin(x)/x, x, 0);"),
            code("matrix([1/2, x^2], [sqrt(2), %pi]);"), code("'diff(g(x,y), x, 1, y, 2);"), code("box(x^2+1);"),
            code("conjugate(z), declare(z, complex);"), code("binomial(n, k);"),
        ], []),
        "07-multi-statement": ([
            code("a: 3$ b: a + 4$ a*b;"), code("print(\"hello\")$ f(x) := x^2 + 1$ f(3);"),
            code(":lisp-quiet (setq $zz 5)\nzz;"),
        ], []),
        "08-text-unicode": ([
            Cell(kind: .title, input: "Ünïcödé & <special> \"characters\""),
            Cell(kind: .text, input: "Greek: αβγ, math: ∑ ∫ √, emoji: 🙂, tab:\there, ampersand: &amp;"),
            code("\"Ünïcödé string\";"), code("%alpha + %beta;"),
        ], []),
        "09-pagebreak-empty": ([
            Cell(kind: .section, input: "Before the break"), code("1+1;"), Cell(kind: .pageBreak),
            Cell(kind: .section, input: "After the break"), code(""), code("3+3;"),
        ], []),
        "10-display2d-tex": ([
            code("display2d: false$"), code("(x+1)^2/y;"), code("tex(x^2/2);"), code("display2d: true$"),
        ], []),
    ]

    /// Evaluates every code cell of `document` in a fresh Maxima and answers questions in order.
    func evaluate(_ document: WorksheetDocument, answers: [String]) async throws {
        let controller = WorksheetController(document: document)
        await controller.start()
        // The state arrives through the session's event stream, just after start() returns.
        let started = ContinuousClock.now
        while controller.sessionState != .idle, ContinuousClock.now < started + .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.sessionState == .idle, "Maxima started: \(controller.statusMessage ?? "")")
        controller.evaluateAll()
        var left = answers
        let deadline = ContinuousClock.now + .seconds(120)
        while !controller.running.isEmpty, ContinuousClock.now < deadline {
            if let id = controller.asking, !left.isEmpty { controller.answer(left.removeFirst(), for: id) }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.running.isEmpty, "every cell finished")
        controller.flush()
        await controller.shutdown()
    }

    @Test(arguments: sessions.keys.sorted())
    func session(_ name: String) async throws {
        let (cells, answers) = Self.sessions[name]!
        let file = Self.dir.appending(path: "\(name).wxmx")
        if Self.recording {
            let doc = WorksheetDocument(worksheet: Worksheet(cells: cells))
            try await evaluate(doc, answers: answers)
            try WXMXWriter.write(doc.worksheet).write(to: file)
        }
        let data = try #require(try? Data(contentsOf: file), "fixture \(name) missing; record with MACSIMA_RECORD_WXMX=1")
        let saved = try WXMXReader.read(data)
        #expect(saved.warnings.isEmpty, "\(saved.warnings)")

        // Saving again gives the same content.xml.
        let again = try WXMXReader.read(try WXMXWriter.write(saved.worksheet))
        #expect(again.worksheet == saved.worksheet)

        // Reopen, re-evaluate, same results.
        let reopened = WorksheetDocument(worksheet: saved.worksheet)
        try await evaluate(reopened, answers: answers)
        for (old, new) in zip(saved.worksheet.cells, reopened.worksheet.cells) {
            #expect(old.id == new.id && old.input == new.input)
            #expect(Self.comparable(old.outputs) == Self.comparable(new.outputs), "\(name): \(old.input)")
        }
    }

    /// Outputs as compared after a re-evaluation: plots by format, label and
    /// size class (gnuplot may not reproduce the bytes exactly).
    static func comparable(_ outputs: [Output]) -> [String] {
        outputs.map { output in
            switch output {
            case .image(let data, let format, let label, _): "image \(format) \(label ?? "-") \(data.count > 1000)"
            default: String(describing: output)
            }
        }
    }
}
