# Phase 3 report: the daily driver

2026-10-19 to 2026-10-20 · macOS 26.5.1 (arm64) · Xcode 26.6, Swift 6.3.3 · Homebrew Maxima 5.50.0 on SBCL 2.6.9 · wxMaxima 26.09.0 as the reference

**Result: Phase 3 is built, and all three checkpoints are approved** (A and B on 2026-10-19, C on 2026-10-20). The exit criterion, a week of real work without falling back to wxMaxima, starts now.

Every item marked for Phase 3 in `docs/PARITY.md` is now done or deferred by agreement (see [Still missing from PARITY.md](#still-missing-from-paritymd)).

## Summary

- **Part A, the editor.**
  - **Editing.** Code and text cells are `NSTextView`s on TextKit 2. Each cell's editor lives as long as the document, so undo survives scrolling.
  - **Code cells:** Maxima syntax colours, the matching bracket, auto-indent and Cmd+/.
  - **Moving around:** Up and Down cross cells, and Find and Replace covers the whole worksheet.
  - **Answers and errors:** a question's answer sits on its line. Errors are marked as wxMaxima marks them: the failing statement, the spot, and the explanation with its marker.
  - **Labels:** no guessed input labels after opening a file.
  - **Windows:** closing one asks to save and stops only that window's Maxima.
  - **Appearance:** dark mode everywhere, and a zoom that is saved in the file.
- **Part B, math output.**
  - Long outputs break into lines at the window width, after wxMaxima's BreakLines.
  - Copy as Maxima input, LaTeX, MathML or a picture.
  - Select whole cells to copy, cut, paste or delete them.
  - Fold sections and hide cells.
  - Image cells, page breaks, and text formatting in text cells.
  - Animations with play and pause; SVG plots and `wxdraw`.
- **Part C, the Maxima side.**
  - **Autocomplete** (Esc or Ctrl+Space), with function templates whose `<arguments>` Tab steps through.
  - **The Maxima manual** in a sidebar (F1).
  - **The sidebar's other panels:** Contents and Variables.
  - **A status bar** with busy time and Maxima's CPU use.
  - **The debugger:** controls for `(dbm:N)` prompts, with Xcode's keys, the stop's location, and Debug on Error.
  - **Lisp mode** after `to_lisp()`.
  - **Interrupting a question.**
  - **Export** to HTML, LaTeX and `.mac`, and `wxworksheettohtml()` in a cell.
  - **`.wxm` files:** open and save.
  - **A Settings window.**
- **Tests:**
  - **Unit and integration tests:** 179 Swift Testing tests in 42 suites pass in about 40 s (`swift test`, "Test run with 179 tests"). Of these, 21 run the real Maxima.
  - **Key scripts:** 28 scripts drive the debug app; all pass. Some need a fixture file; `CLAUDE.md` lists them.
  - **UI tests:** 11 XCUITest tests type real keys; all pass.
- **History.** 49 commits.
- **Code.** About 13,000 lines of Swift in `Sources/`.

## Screenshots

All are in `docs/phase3-screenshots/`, with a table of what each shows in its README:
- **Checkpoint A:** `01-light.png` to `08-close-edited.png`.
- **Checkpoint B:** `09-part-b.png` to `14-wxdraw-svg.png`.
- **Checkpoint C:** `15-completion.png` to `25-fonts.png`.

Line-breaking before-and-after snapshots are in `docs/phase3-snapshots/`.

## What works

**Editor** (`CellTextView`, `MaximaTokenizer`):
- Syntax colours for comments, strings, numbers, keywords, Lisp symbols and `:lisp` lines, and Maxima's own built-ins.
- The matching bracket, auto-indent, Cmd+/ and Find and Replace (one undo step).
- Up and Down across cells, and Shift+Up and Down to select whole cells.

**Autocomplete** (`MaximaCompletion`, `CompletionPopup`):
- **Where entries come from:** Maxima's 2,395 names, wxMaxima's 2,029 built-in templates (`builtin_commands.txt`, copied with its notices), and the worksheet's own names and `f(x) :=` and `define` definitions. Your own definition of a function replaces Maxima's template.
- **How it behaves:** one match is inserted at once. Several open a list that narrows as you type.
- **Templates:** a template's first argument is selected; Tab and Shift+Tab step through the rest.

**Manual** (`macsima.lisp`, `MaximaHelp`, `HelpPanel`):
- **What you see:** the text manual, the same text `describe` prints.
  - Every exact match is shown, without `describe`'s question.
  - Prose is rewrapped to the panel; call forms and examples stay monospaced.
  - The manual's ‘references’ and `*note x::` are links.
  - Related topics, Back and a search field.
- **How it asks Maxima:** lookups use no input label and wait while Maxima is busy or asking a question.

**Sidebar and status bar**:
- **Contents:** the headings; the focused section is marked, and a click unfolds what hides its target.
- **Variables:** watched names or Add All.
  - One query after each evaluation brings every value; functions show their definition.
  - The list is saved in the file the way wxMaxima saves it.
- **Status bar:** Maxima's own messages; while Maxima works, a clock and its CPU use, sampled over its process group; afterwards how long it took.

**Modes**:
- **Questions:** Interrupt while one waits ends the cell as interrupted.
- **Debugger:**
  - At `(dbm:N)`: buttons, a command field, F6, F7 and ⌃⌘Y, and the file, line and source line where Maxima stopped.
  - Debug on Error sets `debugmode`, and is set again after a restart.
  - Breakpoints work in files loaded with `load` or `batchload`.
- **Lisp mode:** cells go to Lisp without input labels; the status bar has a note and Return to Maxima.

**Files and export**:
- **`.wxm`:** opens and saves, image cells included.
- **HTML:** one file, native MathML, images inside it.
- **LaTeX:** a `.tex` file plus `<name>_img/`. Every `.wxmx` fixture compiles with LuaLaTeX, in a test.
- **`.mac`:** as wxMaxima's ExportToMAC writes it.
- **From a cell:** `wxworksheettohtml("file.html")` exports too.
- **Open Recent** comes with macOS.

**Settings**:
- **Maxima side:** Maxima and gnuplot paths, with a found/not-found check.
- **Live:** Abort on error and the plot format (PNG or SVG), applied to running worksheets at once.
- **Fonts and sizes:** code font and size, text size (headings follow) and math size, shown at once.
- **New worksheets:** the zoom they start with.
- **Test isolation:** key scripts and UI tests use a settings store of their own, so they never touch yours.

## Bugs found and fixed on the way

- **Break commands hung.** A `:break` or `:info` line hung its cell. After any `:lisp-quiet` line, Maxima prints no prompt for break commands (`*mread-prompt*`, `mdebug.lisp`). The session now wraps them so exactly one prompt comes.
- **A compiler note looked like a help reply.** SBCL printed a note quoting `macsima.lisp`'s source, tag names and all, and the scanner took it for a reply. The file now sits in `<suppressOutput>`, as the glue does, and an unused binding that caused the note is gone.
- **Blank math after a stuck render.** One render that never got the page's size kept the shared renderer busy, so every later output stayed blank. Renders now give up after 10 s; the key-script dumps count those as `renderTimeouts`.
- **The `to_lisp()` cell lost its label.** Lisp mode's state change arrived before that cell's start. Labels are now decided by the statement itself.
- **`proc_listpgrppids` returns a count of pids, not bytes.**
- **Earlier in Phase 3:**
  - Undo did nothing after a cell scrolled away (editors are now kept for the document's lifetime).
  - Find's marks showed only in the cell whose selection changed (TextKit 2 needs its fragments redrawn).
  - A larger stack frame in the recursive translator crashed a full test run (frames are kept small).

## What differed from BOOTSTRAP.md (updated there)

- **Help.** BOOTSTRAP planned the HTML manual via `html-manual-keywords`. Homebrew's 5.50.0 ships the HTML index without the pages, so the text manual it is (agreed at step 10).
- **Macsima's own Lisp.** `macsima.lisp` sits next to the unmodified `wxMathML.lisp` and adds one tag per reply: `macsima-help`, `macsima-values` and `macsima-variable-names`.
- **Background queries.** wxMaxima queries one variable per round trip. Macsima's `macsima-values` brings them all in one.
- **Abort on error** now matches wxMaxima's: the rest of the cell and the queued cells are not run. Before, Macsima skipped only the rest of the cell. Cells keep their old outputs until they run.
- **Break commands and debugger annotations.** The `:lisp-quiet` prompt quirk, the `^Z^Z file:line::` marker, and the `;` an expression needs in the debugger are now in the protocol section.
- **Roadmap.** BOOTSTRAP estimated 8 to 12 weeks for Phase 3. With Claude Code it took two days of sessions, plus your use between checkpoints.

## Still missing from PARITY.md

**Settled after the report (2026-10-20).** Five Phase 3 items were open when the report was first written. You agreed to finish the small ones and defer the large one; all are now resolved:
- **Box labels:** done. The name shows small above the box; `box(expr, highlight)` is red text without a box.
- **Plot resolution:** done for `wxplot2d` and friends and their animations: drawn at 2×, marked `ppi="192"`, shown by ppi. `wxdraw` plots stay 1× (later).
- **Cursor position (`activecell`):** done, saved and restored as wxMaxima counts it.
- **Jump to error:** done, Cell › Go to Next Error (⌘') and Previous Error (⌘⇧").
- **Selecting text inside math:** deferred past Phase 3 (needs math in the editor's own text).

**Deferred by agreement:**
- Selecting text inside math directly in the worksheet.
- Arrow keys stopping on outputs.
- Greek letters with Esc (Esc completes now).

**Left for later in PARITY.md:**
- **Completion:** file names, ezunits units and demo files; completing as you type.
- **Debugger:** a breakpoint gutter.
- **Values:** watched values shown as 2D math.
- **Export:** HTML flavours (MathJax, SVG, bitmap) and a `.wxmx` attached to exports; RTF and SVG copies; GIF export of animations.
- **Settings:** colours and the `wxmaxima-init` file.
- **Contents:** reordering sections from the contents panel.
- **Selection:** drag-selecting cells; pasting formatted text.
- **Tooling:** a diff viewer.

## Still untested

- **LDB**, SBCL's low-level debugger.
- **Paths with spaces or non-ASCII characters**, for Maxima, files and exports.
- **A second Maxima release**, and a Lisp without threads.
- **Copying and pasting cells** between Macsima and a running wxMaxima.
- **`.wxm` files with images written by wxMaxima itself:** only checked against its source.
- **A `.wxmx` with a watch list written by wxMaxima:** the format is taken from its source, and no fixture has one.
- **The HTML export in browsers other than WebKit:** MathML is standard in current Chrome and Firefox, but not looked at.
- **Ctrl+Space on a Mac without the input-source shortcut:** on this Mac the system takes it; Esc was tested instead.
- **Mouse clicks in the completion list:** only tested by keyboard.
- **Long real use:** memory and speed over a week of work. That is the exit test now under way.
- **Two timing tests are flaky under a fully loaded machine:** the CPU-share test (its floor is now 20%) and `exitsBeforeConnectingIsRetriedThenFails` (a fake Maxima that exits at once was not noticed within 30 s, once). Both pass alone, the second 10 out of 10.

## The user manual

`docs/MANUAL.md` describes every feature by task, with its keys and where Macsima differs from wxMaxima. Showing it inside the app is for later.
