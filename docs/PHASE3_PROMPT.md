Read CLAUDE.md, docs/BOOTSTRAP.md, docs/PARITY.md, docs/WXMX_COMPAT.md and docs/PHASE2_REPORT.md. We are doing Phase 3: the daily driver. The goal is that I can do a week of real work in Macsima without falling back to wxMaxima, with a UI that is better than wxMaxima's, not a copy of it.

docs/PARITY.md is the backlog: every item marked for Phase 3 must end as done, or as deferred with a reason I agreed to. Keep PARITY.md and WXMX_COMPAT.md current after every step. Phase 3 has three parts, each ending with a checkpoint where you stop, show me what changed (screenshots and a short summary), and wait for my answer. I will use the app between parts and may send fixes first.

Same rules as before: one commit per step, `swift build` and `swift test` (N > 0) before each commit, the key scripts must keep passing, never touch my wxMaxima settings or my own worksheets.

Part A: the editor
1. UI tests. Propose how to test real keystrokes: an XCUITest target, or granting Terminal Accessibility. Tell me exactly what I need to approve, then wait for my answer. Keep the key-script driver either way.
2. Editor on AppKit. Move code and text cells to NSTextView (TextKit 2), hosted in SwiftUI, if that is what it takes for the items below. Keep SwiftUI everywhere else. Keep undo working.
3. Editing features: Maxima syntax highlighting (comments, strings, numbers, keywords, built-ins from `wxxml-symbols`); matching-bracket highlight; arrow keys moving between cells at the first and last line; Find and Replace across the worksheet (Cmd+F, Cmd+Opt+F); auto-indent; comment/uncomment (Cmd+/).
4. The four differences I saw in wxMaxima: answers on the same line as the question; the first error line marked; no guessed input labels after opening a file (show labels only after evaluation, as wxMaxima does); syntax highlighting (done in step 3).
5. Window behaviour: closing a window with unsaved changes asks to save and shuts down that Maxima (test it); dark mode across editor and math; zoom (Cmd+plus and minus), saved in the file as wxMaxima does.
Checkpoint A.

Part B: math output
6. Long outputs wrap to the window width. Research how wxMaxima breaks lines, then pick an approach (for example breaking the MathML at top-level operators, or measuring and re-rendering). Show me before-and-after snapshots in docs/phase3-snapshots/.
7. Copy: as Maxima input (linear form via `altCopy`, not the image), as LaTeX (via `tex()` or a translator), as MathML, and as an image. Cross-cell selection of whole cells with copy and paste.
8. Show what is kept but hidden today: folding of sections, hidden cells, text formatting, image cells, page breaks. Animations (`slide`) with play and pause, SVG plots, `wxdraw`.
Checkpoint B.

Part C: the Maxima side
9. Autocomplete from `wxxml-symbols` plus my own definitions, with function templates (argument placeholders).
10. Help: show the Maxima manual entry for the symbol under the caret (`describe` or the HTML manual via `html-manual-keywords`), in a side panel or popover.
11. Panels: variables/watch panel (`variables`, `watch_variables_add`), a status bar (`statusbar`, busy time), a table of contents built from section cells.
12. Modes: a usable debugger UI for `(dbm:N)` prompts, Lisp mode after `to_lisp()`, and interrupting while a question waits.
13. Export and files: HTML and LaTeX export (and the `worksheetexport` tag), `.mac` export, `.wxm` read and write, recent files.
14. Settings window: Maxima and gnuplot paths, fonts and sizes, abort-on-error, plot format (PNG or SVG), default zoom.
Checkpoint C.

15. Write docs/PHASE3_REPORT.md: what works, screenshots, what differed from BOOTSTRAP.md (update it), what is still missing from PARITY.md and why, what is untested. Update the "Current phase" section of CLAUDE.md to: Phase 3 done, my week of real use in progress.

Do not start Phase 4 or any packaging. Stop when the report is written and show me its summary.
