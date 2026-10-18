# Phase 2 report: minimal worksheet

2026-10-18 · macOS 26.5.1 (arm64) · Xcode 26.6, Swift 6.3.3 · Homebrew Maxima 5.50.0 on SBCL 2.6.9 · wxMaxima 26.09.0 (Homebrew) as the reference

**Result: the exit criterion is met.**
- A worksheet saved by Macsima reopens and re-evaluates with the same results. A test does this for ten sessions on every run, against the real Maxima.
- Macsima opens the 11 readable sample files from wxMaxima's repository and the files the installed wxMaxima wrote.
- The installed wxMaxima loads, evaluates and saves eight of the ten Macsima-written sessions.
  - The other two can't be checked in batch mode: it stops at errors and questions without saving. Open those by hand (listed below).
- Every gap is recorded in `docs/WXMX_COMPAT.md`, and every feature gap in `docs/PARITY.md`.

## Summary

- **App.** A macOS 26 document app:
  - the code lives in the Swift package;
  - a thin app target is generated from `project.yml` with XcodeGen and built with `xcodebuild`;
  - it is ad-hoc signed, with no sandbox;
  - `.wxmx` is declared as an imported type with handler rank Alternate, so wxMaxima stays the default.
- **Worksheet.**
  - Cells with stable UUIDs: title, section, subsection, text and code. Deeper headings and page breaks come from files.
  - Code cells show `(%iN)` and `(%oN)` labels.
  - Shift+Return evaluates a cell, Cmd+R evaluates all, Cmd+. interrupts, Cmd+0 to Cmd+4 insert cells.
  - Undo works for structural edits and typing.
- **Evaluation.**
  - One Maxima per window, started on open and shut down on close.
  - Events are batched every 100 ms.
  - Errors show with their text; questions get an inline answer field.
  - Plots are read into the document the moment they arrive (pngcairo when gnuplot has it).
  - The toolbar has the state, a busy indicator, Interrupt and Restart.
  - Quitting the app leaves no Maxima process.
- **Math.** WXMLKit translates Maxima's XML, and wxMaxima's saved dialect, to MathML. One shared WebKit view renders it to cached images, and clicking an output gives a live, selectable view.
- **Files.** `.wxmx` is read and written the way wxMaxima 26.09 does, checked against its source, its manual, its sample files and its batch-mode re-saves:
  - nothing it doesn't understand is dropped;
  - decompression is capped and unsafe paths are rejected;
  - extreme nesting is refused.
- **Tests:**
  - 96 Swift Testing tests in 21 suites pass in about 11 s (`swift test`, "Test run with 96 tests").
  - Three key scripts drive the real app through the editor, evaluation and save (`Tests/Fixtures/keyscripts/run.sh editor-basics|eval-basics|save-basics`). All pass.

## Screenshots

Window-only captures (`screencapture -l`) in `docs/phase2-screenshots/`:

| File | What it shows |
| --- | --- |
| `01-display-forms.png` | A saved session: integral, sum, limit, matrix, derivative, box, conjugate, binomial |
| `02-plots.png` | Two plots read into the document, with the empty `(%o1)` after a plot |
| `03-errors.png` | A math error, a syntax error, `error()`, a Lisp error, an error with an expression |
| `04-question.png` | Two questions answered inline; answers saved as wxMaxima saves them |
| `05-wxmaxima-resave.png` | The same display-forms session after wxMaxima evaluated and re-saved it: it renders the same |
| `06-wxmaxima-sample-banner.png` | wxMaxima's `all-celltypes.wxmx` with the banner listing what is kept but not shown |

Rendering snapshots of 25 fixture outputs and a plot are in `docs/phase2-snapshots/`. They include before-and-after sheets for the rendering fixes you asked for at the checkpoint.

## Rendering measurements (step 3)

200 math outputs in a lazy stack, scrolled top to bottom and back at 60 Hz (`macsima-render bench`; raw JSON in `docs/phase2-snapshots/measurements/`).

| | One web view per output | One shared web view rendering cached images (chosen) |
| --- | --- | --- |
| First screen | 319–333 ms | 651 ms |
| WebKit content processes | 38–52, one per web view | 1 |
| Memory | 1.2–1.6 GB in WebKit + 30 MB app | 38–41 MB in WebKit + 42 MB app |
| Scrolling down: hitches / worst frame | 144–148 of about 325 frames / 264 ms | 3 / 34 ms |
| Scrolling up | 129–138 hitches, worst 59–371 ms | 0 hitches, worst 16.8 ms |

The first measurement of the shared renderer (285 ms, no hitches) was wrong. A bug made it return the previous output's image, caught when the editor showed the wrong result. `macsima-render verify` now compares 24 concurrent renders pixel by pixel with fresh web views, and they are identical. Correct images cost a slower first screen and three small hitches.

## What works

| Area | Status | How it was checked |
| --- | --- | --- |
| App bundle with document type | done | `xcodebuild`; the `Info.plist` has `net.sf.wxmaxima.wxmx` as an imported type, rank Alternate |
| Editor: cells, kinds, typing, Return vs Shift+Return, insert shortcuts, undo, delete | done | `editor-basics` key script, `WorksheetDocumentTests` |
| Evaluation: results, labels, plots, errors, questions, Cmd+., Restart, Cmd+R | done | `eval-basics` key script, `EvaluationMappingTests` |
| No Maxima left after quitting | done | A quit event while Maxima runs: the app exits in about 1 s, and `pgrep` finds no maxima, sbcl or gnuplot |
| MathML for every transcript chunk, plus wxMaxima's saved dialect | done | 31 transcript snapshots; 679 chunks from `.wxmx` fixtures translate with only `slide` unknown |
| `.wxmx` read and write, round trip, untrusted input | done | `WXMXTests`: rich-model round trip, 11 samples, zip bomb, `../` paths, nesting |
| Save from the app, reopen, re-evaluate | done | `save-basics` key script; `SessionFixtureTests` re-evaluates ten saved sessions in a fresh Maxima |
| wxMaxima loads Macsima's files | 8 of 10 in batch mode | Re-saves in `Tests/Fixtures/wxmx/wxmaxima-written/*-resaved.wxmx`, compared cell by cell |
| Macsima loads wxMaxima's files | done | All re-saves and samples read without loss |

## Files to open by hand in wxMaxima

Batch mode can't check these two. Please open them in wxMaxima and see that they display, and that re-evaluating works:
- `Tests/Fixtures/wxmx/macsima-written/03-errors.wxmx`: batch mode stops at the first error without saving.
- `Tests/Fixtures/wxmx/macsima-written/04-question.wxmx`: batch mode stops at questions.

`07-multi-statement.wxmx` loads too, but wxMaxima's batch mode hangs on its `:lisp-quiet` cell. It waits for a prompt that never comes, the same hang Macsima fixed (`3287f93`). Opening it by hand should work.

Never touching your wxMaxima settings:
- Every batch run used a private settings file (`-f`) and a scratch `HOME`.
- Before the first run, `~/Library/Preferences/net.sf.wxMaxima.plist`, `wxMaxima Preferences` and everything in `~/.maxima` were backed up and checksummed. After every run the checksums matched, so nothing needed restoring.

## Bugs found and fixed on the way

- **MaximaKit:** a `:lisp-quiet` line in a cell made the session wait forever. A replay test proved it first (`3287f93`). The only API addition is `additionalSetupLines`, used for pngcairo (`b0ed8e4`). Default behaviour is unchanged.
- **Rendering:**
  - WebKit raises stretchy parentheses around short content, sizes each radical to its own content and misplaces overline accents. Fixed by choosing among variants side by side (`macsima-render lab`).
  - Binomials lost their parentheses, and differentials were spaced too wide. Both fixed.
- **Shared renderer:** it returned the previous output's image, from a late size report of the replaced page (`629c84c`).
- **Spawning under the test runner:** a test thread's 512 KB stack overflowed on a 155-level sample, and a 100,000-level file crashed the tree code. The parsers now refuse more than 512 levels, and the translator renders more than 400 as text (`09fb4a2`).
- **Cross-compatibility:** found by comparing with wxMaxima's re-saves, and fixed:
  - plain-text output must be `type="ASCII-Art"`;
  - empty results after plots must be kept;
  - saved labels carry a tab;
  - wxMaxima's own files lose the binomial's parentheses.

## What differed from BOOTSTRAP.md (updated there)

1. **One web view per output doesn't scale.** WebKit starts a process for each web view; see the measurements. BOOTSTRAP.md now records the shared renderer.
2. **WebKit's MathML needs workarounds.** Non-stretchy fences for short content, a radical strut, and `menclose` for the conjugate overline.
3. **The `.wxmx` format.** The confirmed facts are now in BOOTSTRAP.md:
   - zip entries in a fixed order, all stored;
   - `version="1.5"`;
   - `uuid` on cells;
   - deeper headings as `subsection` with `sectioning_level` 4 to 6;
   - outputs in wxMaxima's own dialect, split at `breakline`;
   - answers as an editor inside the output;
   - plain text as `ASCII-Art`.
4. **Layout.** BOOTSTRAP.md still listed `Resources/lisp/`, but the glue Lisp moved to `Sources/MaximaKit/Resources/` in Phase 1. Also new since BOOTSTRAP.md was written: `MacsimaUI`, `project.yml`, the `maxima-session` and `macsima-render` tools, and `Tests/Fixtures/keyscripts`.
5. **Matrices.** `bracketParens` means square brackets, Maxima's default matrix style. The step 3 snapshots had used round ones.
6. **wxMaxima's batch mode.** `-b` saves but never exits, and stops at errors and questions. `-f` and a scratch `HOME` keep a run away from the user's settings.

## Still untested

- **Real keystrokes.** Terminal is not trusted for Accessibility here, even after the restart (`AXIsProcessTrusted()` is false; System Events refuses keystrokes). So the editor was driven by key events synthesized inside the app, through `NSApp.sendEvent`.
  - Unverified: whether the physical Delete key triggers Cmd+Shift+Delete. The shortcut works with the U+0008 character SwiftUI registers.
  - Unverified: typing with a real keyboard in general.
- **Closing a window with unsaved changes.** The window's shutdown path (`onDisappear`) was not driven by a test. Quitting was tested.
- **Questions in batch mode.** `03-errors` and `04-question` in wxMaxima (see above).
- **Interrupting** while a question waits, the debugger, `to_lisp()` in the window, SVG plots, animations, very large worksheets (more than 500 cells) in the editor, and dark mode beyond two snapshots.
- **Files from older wxMaxima releases** other than the repository samples.

## What changes Phase 3

- **The editor is SwiftUI `TextEditor`s, with no AppKit so far.** Cross-cell selection, find and replace, and autocomplete will probably need `NSTextView`. Expect that work in Phase 3.
- **Math is images.** Selection works only after a click swaps in a live view. Copy as Maxima input needs a real linear form, the `altCopy` route.
- **Long outputs don't wrap,** and they run past the window. wxMaxima breaks them over lines; MathML in WebKit doesn't.
- **Kept, not shown:** folding, hidden cells, text formatting, zoom, `activecell`, image cells and animations. They are all preserved and listed in WXMX_COMPAT.md and PARITY.md, ready to be turned on one by one.
- **Testing without Accessibility.** The key-script driver (debug builds only) is how UI behaviour gets tested here. Granting Terminal Accessibility, or adding an XCUITest target, would allow real keystrokes.
