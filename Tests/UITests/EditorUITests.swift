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
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MacsimaUITest", "YES"]
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
}
