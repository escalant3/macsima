// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest

/// Real keystrokes against the Debug app, through XCUITest. Each test starts
/// from a fresh untitled worksheet; restored windows are ignored, and the app
/// refuses to run if a document outside `.build/` is open (TestGuard).
final class EditorUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // English whatever the system language: the tests find menu items by title.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MacsimaUITest", "YES",
                               "-AppleLanguages", "(en)"]
        app.launch()
    }

    @MainActor
    override func tearDown() async throws {
        // The untitled worksheet is thrown away with the app.
        app.terminate()
    }

    @MainActor
    private func waitForReady() {
        let state = app.staticTexts["session-state"]
        let ready = NSPredicate(format: "value == 'Ready' OR label == 'Ready'")
        expectation(for: ready, evaluatedWith: state)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testEvaluateWithShiftReturn() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("integrate(sin(x),x);")
        app.typeKey(.return, modifierFlags: .shift)

        let output = app.descendants(matching: .any)["cell-output-0-0"]
        XCTAssertTrue(output.waitForExistence(timeout: 20))
        XCTAssertEqual(output.label, "-cos(x)")
        // Shift+Return moves on to a new cell, which takes the typing.
        XCTAssertTrue(app.textViews["cell-input-1"].waitForExistence(timeout: 5))
        app.typeText("1+1;")
        XCTAssertEqual(app.textViews["cell-input-1"].value as? String, "1+1;")
    }

    @MainActor
    func testCompleteWithEsc() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        // One match: inserted at once.
        app.typeText("integrate_use_r")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(input.value as? String, "integrate_use_rootsof")
        // Several: the list; Down, Return takes the second, its first argument selected.
        app.typeText("$ integrat")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["completion-list"].waitForExistence(timeout: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(input.value as? String, "integrate_use_rootsof$ integrate(<expr>, <x>, <a>, <b>)")
        app.typeText("sin(t)")
        app.typeKey(.tab, modifierFlags: [])
        app.typeText("t")
        XCTAssertEqual(input.value as? String, "integrate_use_rootsof$ integrate(sin(t), t, <a>, <b>)")
    }

    @MainActor
    func testF1OpensTheManual() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("expand(x)")
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey(.F1, modifierFlags: [])
        let entry = app.descendants(matching: .any)["help-entry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["help-search"].value as? String, "expand")
    }

    @MainActor
    func testUndoTypingThenDeleteCell() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("a:1;")
        app.typeKey("1", modifierFlags: .command)   // insert a text cell
        XCTAssertTrue(app.textViews["cell-input-1"].waitForExistence(timeout: 5))
        app.typeText("prose")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(app.textViews["cell-input-1"].value as? String, "")
        // The physical Delete key with Command and Shift deletes the cell.
        app.typeKey(.delete, modifierFlags: [.command, .shift])
        XCTAssertFalse(app.textViews["cell-input-1"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textViews["cell-input-0"].value as? String, "a:1;")
    }

    /// A real click on a cell's bar, a Shift-click, then Cmd+C and Cmd+V
    /// (the app copies to a private pasteboard under test).
    @MainActor
    func testCopyAndPasteWholeCells() throws {
        waitForReady()
        let first = app.textViews["cell-input-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        app.typeText("p:1;")
        app.typeKey("0", modifierFlags: .command)
        app.typeText("q:2;")
        app.descendants(matching: .any)["cell-bar-0"].click()
        XCUIElement.perform(withKeyModifiers: .shift) { app.descendants(matching: .any)["cell-bar-1"].click() }
        app.typeKey("c", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(app.textViews["cell-input-3"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["cell-input-2"].value as? String, "p:1;")
        XCTAssertEqual(app.textViews["cell-input-3"].value as? String, "q:2;")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(app.textViews["cell-input-2"].waitForExistence(timeout: 2))
    }

    /// Real clicks and a drag on a math output select parts of it: a click
    /// the symbol under the pointer, a second click the row holding it, a
    /// drag what it covers. Cmd+C copies the part as Maxima input, which is
    /// pasted into the next cell to check it.
    @MainActor
    func testSelectInsideMath() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("a+b+c+d+e;")
        app.typeKey(.return, modifierFlags: .shift)
        let output = app.descendants(matching: .any)["cell-output-0-0"]
        XCTAssertTrue(output.waitForExistence(timeout: 20))
        XCTAssertEqual(output.label, "e+d+c+b+a")
        Thread.sleep(forTimeInterval: 1)   // the picture and where its parts are
        let next = app.textViews["cell-input-1"]
        func copied() -> String? {
            app.typeKey("c", modifierFlags: .command)
            next.click()
            app.typeKey("a", modifierFlags: .command)
            app.typeKey("v", modifierFlags: .command)
            return next.value as? String
        }
        // The label column is 52 points and the gap 19 at 100%: the first symbol follows.
        let first = output.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 75, dy: 0))
        first.click()
        XCTAssertEqual(copied(), "e")
        first.click()
        first.click()
        XCTAssertEqual(copied(), "e+d+c+b+a")
        // From the first symbol to the third: e+d.
        first.press(forDuration: 0.1, thenDragTo: first.withOffset(CGVector(dx: 30, dy: 0)))
        XCTAssertEqual(copied(), "e+d")
        // The context menu copies the selected part too.
        first.press(forDuration: 0.1, thenDragTo: first.withOffset(CGVector(dx: 30, dy: 0)))
        output.rightClick()
        app.menuItems["Copy as LaTeX"].click()
        next.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(next.value as? String, "e + d")
        // Escape goes out to the whole result, then back to the cell's input.
        first.click()
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        app.typeText("#")
        XCTAssertEqual(input.value as? String, "a+b+c+d+e;#")
    }

    /// A real click on a section's triangle folds it; clicking the "folded"
    /// line unfolds it.
    @MainActor
    func testFoldSection() throws {
        waitForReady()
        let first = app.textViews["cell-input-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        app.typeKey("3", modifierFlags: .command)
        app.typeText("Section")
        app.typeKey("0", modifierFlags: .command)
        app.typeText("inside;")
        XCTAssertTrue(app.textViews["cell-input-2"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["cell-disclosure-1"].click()
        XCTAssertFalse(app.textViews["cell-input-2"].waitForExistence(timeout: 2))
        app.descendants(matching: .any)["cell-folded-1"].click()
        XCTAssertTrue(app.textViews["cell-input-2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["cell-input-2"].value as? String, "inside;")
    }

    /// An animation plays when its Play button is clicked.
    @MainActor
    func testAnimationPlays() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("wxanimate_framerate:10$ with_slider(a,[1,2,3,4],a*x,[x,0,1]);")
        app.typeKey(.return, modifierFlags: .shift)
        let frame = app.descendants(matching: .any)["animation-frame"]
        XCTAssertTrue(frame.waitForExistence(timeout: 20))
        XCTAssertEqual(frame.value as? String ?? frame.label, "1 / 4")
        app.descendants(matching: .any)["animation-play"].click()
        let moved = NSPredicate(format: "value != '1 / 4' OR label != '1 / 4'")
        expectation(for: moved, evaluatedWith: frame)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testArrowKeysMoveBetweenCells() throws {
        waitForReady()
        let first = app.textViews["cell-input-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        app.typeText("abc;")
        app.typeKey("0", modifierFlags: .command)   // a new code cell below
        app.typeText("xyz;")
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])     // into the first cell, same column
        app.typeText("1")
        XCTAssertEqual(first.value as? String, "abc1;")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeText("2")
        // The caret was at column 4 ("abc1"), so it lands at the end of "xyz;".
        XCTAssertEqual(app.textViews["cell-input-1"].value as? String, "xyz;2")
    }

    /// Up and Down stop on outputs (printed text, math, errors); Return goes
    /// into a result, Left and Right move between its parts, Shift grows a
    /// run or a matrix block, Escape goes back out. Cmd+C copies what is
    /// selected, pasted into the last cell to check it.
    @MainActor
    func testArrowKeysStopOnOutputs() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("print(\"hi\")$ a+b+c;")
        app.typeKey(.return, modifierFlags: .shift)
        app.typeText("1/0;")
        app.typeKey(.return, modifierFlags: .shift)
        app.typeText("matrix([1/2,x],[3,4]);")
        app.typeKey(.return, modifierFlags: .shift)
        let last = app.textViews["cell-input-3"]
        XCTAssertTrue(last.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["cell-output-2-0"].waitForExistence(timeout: 20))
        let sum = try XCTUnwrap(app.descendants(matching: .any)["cell-output-0-1"].label)
        Thread.sleep(forTimeInterval: 1)
        func key(_ k: XCUIKeyboardKey, _ flags: XCUIElement.KeyModifierFlags = [], times: Int = 1) {
            for _ in 0..<times { app.typeKey(k, modifierFlags: flags) }
        }
        func copied() -> String? {
            app.typeKey("c", modifierFlags: .command)
            last.click()
            app.typeKey("a", modifierFlags: .command)
            app.typeKey("v", modifierFlags: .command)
            return last.value as? String
        }
        func fromFirstInput() {
            input.click()
            key(.rightArrow, .command)
        }
        // The last input, emptied of what was pasted to check a copy.
        func fromLastInput() {
            last.click()
            app.typeKey("a", modifierFlags: .command)
            key(.delete)
        }
        // Down from the input: the printed text, then the result.
        fromFirstInput()
        key(.downArrow)
        XCTAssertEqual(copied(), "hi")
        fromFirstInput()
        key(.downArrow, times: 2)
        XCTAssertEqual(copied(), sum)
        // Into the result: its first term, two to the right, then Shift grows the run.
        fromFirstInput()
        key(.downArrow, times: 2)
        key(.return)
        key(.rightArrow, times: 2)
        key(.rightArrow, .shift, times: 2)
        let terms = sum.split(separator: "+").map(String.init)
        XCTAssertEqual(copied(), terms[1] + "+" + terms[2])
        // On past the result: the next cell's input, then its error.
        fromFirstInput()
        key(.downArrow, times: 4)
        let error = try XCTUnwrap(copied())
        XCTAssertTrue(error.contains("0"), error)
        // Up from the last input: the matrix; Return gives its first entry,
        // the arrows move between entries, Shift grows a block.
        fromLastInput()
        key(.upArrow)
        key(.return)
        XCTAssertEqual(copied(), "1/2")
        fromLastInput()
        key(.upArrow)
        key(.return)
        key(.rightArrow)
        key(.downArrow)
        key(.leftArrow, .shift)
        XCTAssertEqual(copied(), "matrix([3,4])")
        // Escape goes back out, and from the whole result into its input.
        fromLastInput()
        key(.upArrow)
        key(.return)
        key(.escape)
        key(.escape)
        app.typeText("#")
        XCTAssertEqual(app.textViews["cell-input-2"].value as? String, "matrix([1/2,x],[3,4]);#")
    }

    @MainActor
    func testFindAcrossCells() throws {
        waitForReady()
        let first = app.textViews["cell-input-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        app.typeText("x+1;")
        app.typeKey("0", modifierFlags: .command)
        app.typeText("x^2+x;")
        app.typeKey("f", modifierFlags: .command)
        app.typeText("x")   // straight into the find field
        let status = app.descendants(matching: .any)["find-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "1 of 3")
        app.typeKey("g", modifierFlags: .command)
        XCTAssertEqual(status.value as? String, "2 of 3")
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertEqual(status.value as? String, "3 of 3", "Find Previous wraps")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(status.exists)
        // The focus is on the match: typing replaces the selected x.
        app.typeText("z")
        XCTAssertEqual(app.textViews["cell-input-1"].value as? String, "x^2+z;")
    }

    @MainActor
    func testClosingAnEditedWorksheetAsks() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("1+1;")
        app.typeKey("w", modifierFlags: .command)
        // A new worksheet: macOS's save panel, with Delete, Cancel and Save.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "closing an edited worksheet asks")
        sheet.buttons.matching(identifier: "Cancel").firstMatch.click()
        XCTAssertTrue(input.exists, "Cancel keeps the window")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.buttons["Delete"].click()
        XCTAssertFalse(input.waitForExistence(timeout: 2), "Delete closes it")
    }

    @MainActor
    func testZoomWithCommandPlusAndMinus() throws {
        waitForReady()
        let input = app.textViews["cell-input-0"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        app.typeText("x+1;")
        let before = input.frame.height
        app.typeKey("+", modifierFlags: .command)   // Shift+= on a US keyboard
        app.typeKey("=", modifierFlags: .command)   // and without Shift
        let zoomed = input.frame.height
        XCTAssertGreaterThan(zoomed, before * 1.1, "two steps of 10%: the editor grows")
        app.typeKey("-", modifierFlags: .command)
        app.typeKey("-", modifierFlags: .command)
        XCTAssertEqual(input.frame.height, before, accuracy: 1)
    }

    /// File › Duplicate opens the copy with its name ready to edit; Return
    /// takes the new name. The original is a copy under `.build/uitests/`,
    /// so the duplicate is saved there too.
    @MainActor
    func testRenameAfterDuplicate() throws {
        // Put there by the scheme's pre-action (the test runner is sandboxed).
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let original = repo.appending(path: ".build/uitests/rename.wxmx")
        app.terminate()
        app.launchArguments += [original.path]
        app.launch()
        XCTAssertTrue(app.windows["rename.wxmx"].waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Duplicate"].click()
        let field = app.windows["rename copy"].textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the copy's name is ready to edit")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("renamed")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.windows["renamed"].waitForExistence(timeout: 10)
                      || app.windows["renamed.wxmx"].waitForExistence(timeout: 1),
                      "Return takes the name: \(app.windows.allElementsBoundByIndex.map(\.title))")
    }
}
