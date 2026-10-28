// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MaximaKit
import Testing
import WorksheetKit
@testable import MacsimaUI

/// CellEvent → worksheet output mapping, without a Maxima session.
@MainActor
struct EvaluationMappingTests {
    func setUp() -> (WorksheetController, UUID) {
        let doc = WorksheetDocument()
        let id = doc.worksheet.cells[0].id
        return (WorksheetController(document: doc), id)
    }

    func run(_ events: [CellEvent], _ controller: WorksheetController, _ id: UUID) -> [Output] {
        for e in events { controller.receive(e, for: id) }
        controller.flush()
        return controller.document.worksheet[id]?.outputs ?? []
    }

    let statement = Statement(text: "x;", terminator: .show)

    @Test func resultsAndLabels() {
        let (c, id) = setUp()
        let math = #"<math><lbl altCopy="%o1">(%o1) </lbl><mn>4</mn></math>"#
        let out = run([.started(index: 0, statement), .math(math), .prompt(label: 2), .finished(.completed)], c, id)
        #expect(out == [.math(xml: math)])
        #expect(c.document.worksheet[id]?.inputLabel == 1)
        // The next cell gets the label of the prompt that ended this one.
        let (c2, id2) = (c, c.document.insertCell(.code, after: id, undo: nil))
        _ = run([.started(index: 0, statement), .prompt(label: 3), .finished(.completed)], c2, id2)
        #expect(c.document.worksheet[id2]?.inputLabel == 2)
    }

    @Test func textLinesJoinAndErrorsTakeTheirStatementsText() {
        let (c, id) = setUp()
        let out = run([
            .started(index: 0, statement), .text("hello"), .prompt(label: 2),
            .started(index: 1, statement), .text("expt: undefined: 0 to a negative exponent."),
            .text(" -- an error. To debug this try: debugmode(true);"),
            .error(.maxima, message: "expt: undefined: 0 to a negative exponent."), .prompt(label: 3),
            .finished(.failed(.maxima)),
        ], c, id)
        #expect(out == [
            .text("hello"),
            .error(kind: "maxima", message: "expt: undefined: 0 to a negative exponent.\n -- an error. To debug this try: debugmode(true);"),
        ])
    }

    @Test func errorWithItsMessageInMath() {
        let (c, id) = setUp()
        let math = #"<math>value is <mn>2</mn></math>"#
        let out = run([.started(index: 0, statement), .math(math), .error(.maxima, message: ""), .finished(.failed(.maxima))], c, id)
        #expect(out == [.math(xml: math), .error(kind: "maxima", message: "")])
    }

    @Test func imagesAreReadImmediately() throws {
        let (c, id) = setUp()
        let file = FileManager.default.temporaryDirectory.appending(path: "macsima-test-\(UUID().uuidString).png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        try bytes.write(to: file)
        let xml = #"<math><lbl altCopy="%t1">(%t1) </lbl><img lisp="wxxml-tag">\#(file.path)</img></math>"#
        c.receive(.started(index: 0, statement), for: id)
        c.receive(.math(xml), for: id)
        try FileManager.default.removeItem(at: file)   // gone before the flush, as after a kill
        c.receive(.finished(.completed), for: id)
        #expect(c.document.worksheet[id]?.outputs == [.image(data: bytes, format: "png", label: "%t1")])
    }

    @Test func questionsAndInterrupts() {
        let (c, id) = setUp()
        let prompt = "<math><st>Is </st><mi>y</mi><st> positive?</st></math>"
        c.receive(.started(index: 0, statement), for: id)
        c.receive(.question(prompt), for: id)
        #expect(c.asking == id)
        let out = run([.text("Maxima encountered a Lisp error:"), .text(" User interrupt"), .interrupted,
                       .finished(.interrupted)], c, id)
        #expect(out == [.question(prompt: prompt, answer: nil), .error(kind: "interrupted", message: "Interrupted")])
        #expect(c.asking == nil)
    }

    @Test func sessionDeathIsShown() {
        let (c, id) = setUp()
        let out = run([.started(index: 0, statement), .finished(.sessionDied("Maxima was stopped"))], c, id)
        #expect(out == [.error(kind: nil, message: "Not finished: Maxima was stopped.")])
        #expect(c.running.isEmpty)
    }
}
