# Macsima

A native macOS front end for Maxima, written in Swift, as a personal tool. It does what wxMaxima does (long-term goal: 1:1 feature parity, reached in stages) with a better UI, and without wxWidgets or its dependencies.

Read `docs/BOOTSTRAP.md` before any work. Its wire protocol reference and roadmap are the plan. If the code and the doc disagree, tell me and update the doc.

## Decisions (already made, do not reopen)
- Personal tool first. Sharing is optional later. No packaging, DMG, notarization, bundling or sandboxing work unless I ask.
- Engine: SBCL only. Baseline is Homebrew Maxima 5.50.0 at `/opt/homebrew/bin/maxima`, gnuplot from Homebrew. Never bundle or modify Maxima.
- Platform: arm64 only, macOS 26 (Tahoe) minimum, current Swift and SwiftUI APIs. Ease of coding beats backward compatibility. AppKit is fine where SwiftUI falls short. No UIKit.
- License: GPL-2.0-or-later. Every source file starts with `// SPDX-License-Identifier: GPL-2.0-or-later`. When porting from wxMaxima (including wxMathML.lisp), keep its copyright notices and say so in a comment.
- File format: full `.wxmx` compatibility is the long-term goal. At first, opening files this app wrote is enough. Record every unsupported element or feature in `docs/WXMX_COMPAT.md` (element, read, write, status, what to avoid in wxMaxima). Never silently drop data when reading a file: keep unknown XML, warn on open, write it back where possible.
- Feature parity with wxMaxima is the target, staged by the MVP column in BOOTSTRAP.md. Track gaps, do not hide them.

## Working rules
- Verify protocol claims against a real Maxima process before relying on them. Save captured output under `Tests/Fixtures/transcripts/`.
- Swift Package Manager layout from BOOTSTRAP.md: `MaximaKit` (no UI), `WXMLKit`, `WorksheetKit`, then the app target. Keep the engine testable without a window.
- Swift 6 language mode, strict concurrency. Use an actor for the Maxima session.
- Do not claim something works unless you built and ran it. Say what you could not test.
- Treat `.wxmx` files as untrusted input (size caps on decompression).
- Small commits, one topic each.

## Commands
- Build: `swift build`
- Test: `swift test`. The "Executed 0 tests" line is the XCTest runner and is expected when a package only uses Swift Testing. Read the Swift Testing line instead ("Test run with N tests ... passed") and check that N is above zero.
- UI tests (real keystrokes, XCUITest): `xcodegen generate && xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode -destination 'platform=macOS' test`. Automation Mode is enabled without authentication on this Mac; they take over keyboard and mouse. See `Tests/UITests/README.md`.
- Package platform must be `.macOS(.v26)` in `Package.swift`.
- Maxima: `/opt/homebrew/bin/maxima --version`
- Does my SBCL have threads: `sbcl --noinform --eval '(progn (format t "threads: ~a~%" (if (member :sb-thread *features*) "yes" "no")) (quit))'`

## Current phase
Phase 2 is done: Macsima is a working worksheet app (see `docs/PHASE2_REPORT.md`; earlier phases in `docs/PHASE0_REPORT.md` and `docs/PHASE1_REPORT.md`). Phase 3 (daily driver, `docs/PHASE3_PROMPT.md`) is in progress: Parts A (the editor) and B (math output) are done and approved; Part C (the Maxima side, steps 9 to 14, then the report in step 15) is next. Arrow keys stopping on outputs are deferred past Phase 3.

Facts to keep in mind (details in the reports, BOOTSTRAP.md, WXMX_COMPAT.md and PARITY.md):
- **Build the app.** `xcodegen generate && xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode build`. All code lives in the package (`MacsimaUI`); `App/Macsima` only holds `@main`.
- **Engine.** `MaximaSession` (actor) does all Maxima work; each window's `WorksheetController` owns one and batches its events every 100 ms.
- **Math rendering.** One shared hidden web view (`MathSnapshotRenderer`) renders outputs to cached images; `macsima-render verify` checks the images match their math. Translate math on the main thread (`TranslationCache`): the translator is recursive and capped at 400 levels.
- **`.wxmx`.** `WXMXReader` and `WXMXWriter` in WorksheetKit keep everything they don't understand. Store Maxima's math as one canonical `<math>` element (`WorksheetController.storedMath`) so files round-trip exactly.
- **Editor.** Each cell is an `NSTextView` on TextKit 2 (`CellTextView`); the controller keeps one per cell for the document's lifetime, so undo survives scrolling. Colours and marks are TextKit 2 rendering attributes; after changing them, call `redrawFragments()`, or they don't show.
- **UI tests.** XCUITest (`Tests/UITests/`) for real keystrokes. Key scripts in `Tests/Fixtures/keyscripts/` (`run.sh editor-basics|eval-basics|advance-basics|editor-syntax|undo-scroll|find-basics|errors-basics|close-basics|appearance|wrap-basics|copy-basics|cells-basics|plots-basics|folds-basics|format-basics|complete-basics|help-basics|panels-basics|modes-basics`, plus `save-basics`, `advance-existing`, `close-saved`, `zoom-basics` and `kinds-basics` with a fixture file; `run.sh` refuses on a locked screen and logs when another app takes the focus) drive the debug app. Synthesized key events are posted to the app's event queue; calling `sendEvent` directly breaks undo grouping. Scripts never touch the user's documents or clipboard: they ignore restored windows, the driver refuses to run otherwise, and copies go to a private pasteboard. Screenshots: window only, never the whole screen.
- **Long math** breaks into lines in the page's own script (`MathLineBreaking.swift`), after wxMaxima's BreakLines; `macsima-render verify` checks it. The translator, `MaximaInputText` and `LaTeXTranslator` recurse up to 400 levels on the main thread's stack: keep their recursive functions' frames small (a bigger frame crashed a full test run once).
- **Folding** keeps one flat cell list; a heading's `isFolded` hides its section in the view only. `.wxmx` and `.wxm` write the section into `<fold>`/fold markers.
- **wxMaxima as a reference.** Run it only on copies, with `-f <private ini>` and a scratch `HOME`; check that its settings are unchanged afterwards. Batch mode (`-b`) saves but never exits, and stops at errors and questions.
- **Fixtures.** Re-record session fixtures with `MACSIMA_RECORD_WXMX=1` and translator snapshots with `MACSIMA_RECORD_SNAPSHOTS=1`.
