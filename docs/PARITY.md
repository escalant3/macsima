# Feature parity with wxMaxima

Where Macsima stands against wxMaxima, as of Phase 2 (2026-10-18). The first table follows the "What the GUI owns" table in `docs/BOOTSTRAP.md`, row by row. The second lists what turned up along the way. Status is done, partial or missing. Phase is where the gap belongs, following BOOTSTRAP.md's MVP column and roadmap. File-format details are in `docs/WXMX_COMPAT.md`.

## The GUI table from BOOTSTRAP.md

| Area | wxMaxima | Macsima now | Status | Phase |
| --- | --- | --- | --- | --- |
| Document model | Title, section, subsection, text and code cells (plus deeper headings, images, page breaks), `.wxmx` and `.wxm` | Every `.wxmx` cell kind in the model. The editor creates code, text, title, section and subsection. Deeper headings and page breaks show; image and unknown cells are placeholders, kept and saved back. `.wxmx` read and write; no `.wxm`. | partial | `.wxm` and image cells: 3 |
| Evaluation queue | Splits cells into statements, `;` versus `$`, `:lisp` and `to_lisp()`, adds a missing terminator, one statement at a time | All of it, through MaximaKit (Phase 1). Cells run in order; Cmd+R evaluates all. | done | |
| Error handling | Optionally aborts on error, marks the failing statement and spot in the editor | The rest of the cell is skipped and the error shows with its text. No marking of the failing statement or position in the editor. | partial | 3 |
| Questions and debugger | Answer cells for questions; the `(dbm:N)` debugger and LDB are special cases | Questions show inline with an answer field, and answers are saved the way wxMaxima saves them. The debugger prompt shows as a question; no debugger UI, no LDB. | partial | 3 |
| 2D math | Its own layout engine, selection and copy via `altCopy` | MathML through WebKit, rendered to images by one shared web view. Clicking an output gives a live, selectable view; the context menu copies plain text or MathML. | partial: see the second table | 3 |
| Plots | PNG or SVG from `img`, animations from `slide` | PNG plots (pngcairo when gnuplot has it), read into the document at once. No SVG; animations not shown. | partial | 3 |
| Autocomplete | `wxxml-symbols` and the user's own definitions | none | missing | 3 |
| Variables and status | Watch panel, status bar, CPU polling | Toolbar state (Ready, Evaluating…, waiting for an answer) and a status line for Maxima's own messages (`statusbar`, start-up problems). No watch panel. | partial | 3 |
| Help | Topic names, the HTML manual | none | missing | 3 |
| Export and tooling | HTML, LaTeX, `.mac`, `.wxm` export, undo, search, diff viewer | Undo for cell insert, delete and type changes, and typing. No export, no search, no diff. | partial | 3 |
| Settings | Maxima and gnuplot paths, display options, `wxmaxima-init` | The Maxima path. | partial | 3 |

## Found during Phase 2

| Feature | wxMaxima | Macsima now | Status | Phase |
| --- | --- | --- | --- | --- |
| Animations (`slide`) | Plays frame lists, with sliders | The frames are kept and saved back; the output shows their file names as text | missing | 3 |
| Copy math as Maxima input | Uses `altCopy` and its own text forms | "Copy as Text" gives a rough linear form, fine for simple results and crude for sums, integrals and limits (for example `k=1inf(1)/(k^(2))`) | partial | 3 |
| Selecting text inside math | Directly in the worksheet | Click an output to swap in a live web view, then select | partial | 3 |
| Folded sections | Fold and unfold under headings | Folded cells from files are kept and saved back; a placeholder marks them. No folding in the editor. | missing | 3 |
| Hidden output (`hide`) | Hides a cell's output | Kept and saved back, not applied | missing | 3 |
| Text formatting in text cells | Bold, colours and more, stored on `line` | Kept while the text is unchanged; editing drops it; no formatting tools | missing | 3 |
| Box labels (`boxname`) | Shows the label | The box shows, the label doesn't | partial | 3 |
| Plot resolution | Uses `ppi` to show plots sharp | pngcairo plots are 600×450 at 1×, slightly soft on Retina; `ppi` is kept but not applied | partial | 3 |
| Matrix brackets | `bracketParens`, `angledParens`, `straightParens`, `noneParens`, round by default | All of them | done | |
| Dark mode | Configurable colours | The math images follow the system appearance; the editor uses system colours. Not tested beyond two snapshots. | partial | 3 |
| Line breaking of long outputs | Breaks long expressions over lines | No line breaking: a long output is one wide image that runs past the window's edge (no sideways scrolling yet) | missing | 3 |
| Zoom | Saved in the file, applied | Kept and saved back, not applied | missing | 3 |
| Cursor position (`activecell`) | Saved and restored | Kept from the file, not updated | partial | 3 |
| Real keystrokes | | XCUITest target (`Tests/UITests/`, Phase 3 step 1) types real keys: Shift+Return, Cmd+1, Cmd+Z, Cmd+Shift+Delete. The key-script driver still posts synthesized events for the longer scripts. | done | |
| `.wxmx` timestamps | Local time | ZIPFoundation writes them two hours off here; harmless | partial | later |
| Answer layout | The answer follows the question on the same line | The answer is on its own line below the question (seen by opening 04-question in both apps) | partial | 3 |
| Error marker | Marks an error line in yellow (seen on the first error of 03-errors; the cause is not yet traced in wxMaxima's source) | Error text in red, no marker | partial | 3 |
| Input labels after opening a file | No `(%iN)` until the cell is evaluated again | Guesses `(%iN)` from the first output label; can be wrong after a syntax error. Should match wxMaxima | partial | 3 |
| Syntax highlighting in code cells | Yes | Comments, strings, numbers, keywords, Lisp symbols and `:lisp` lines, terminators, and built-ins from `<wxxml-symbols>` (Phase 3 step 3). Single-letter names in that list (`x`, `a`, `t`, ...) are interned by Maxima's own code, so they stay plain | done | |
| Moving between cells with the arrow keys | Up and Down move the cursor through inputs and outputs, across cells | Only with the mouse | missing | 3 (likely needs `NSTextView` for the caret position) |
| After Shift+Return | The cursor moves to the next cell, or to a new cell at the end | The same (a Phase 2 follow-up, 2026-10-19) | done | |
| Starting the app | Opens an untitled worksheet | The same; untitled worksheets are saved later with Cmd+S (a Phase 2 follow-up, 2026-10-19) | done | |

## Math XML translator (WXMLKit)

Tags the translator doesn't know render as their text content (never dropped) and are listed here. Across the 679 math chunks in the `.wxmx` fixtures and all transcript chunks, `slide` is the only one.

| Tag | Emitted by wxMathML.lisp for | Status |
| --- | --- | --- |
| `slide` | animations (`wxanimate`, `with_slider_draw`) | missing: text only |
