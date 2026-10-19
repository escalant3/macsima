# Feature parity with wxMaxima

Where Macsima stands against wxMaxima, as of Phase 2 (2026-10-18), updated during Phase 3. The first table follows the "What the GUI owns" table in `docs/BOOTSTRAP.md`, row by row. The second lists what turned up along the way. Status is done, partial or missing. Phase is where the gap belongs, following BOOTSTRAP.md's MVP column and roadmap. File-format details are in `docs/WXMX_COMPAT.md`.

## The GUI table from BOOTSTRAP.md

| Area | wxMaxima | Macsima now | Status | Phase |
| --- | --- | --- | --- | --- |
| Document model | Title, section, subsection, text and code cells (plus deeper headings, images, page breaks), `.wxmx` and `.wxm` | Every `.wxmx` cell kind in the model. The editor creates code, text, title, section and subsection. Deeper headings and page breaks show; image and unknown cells are placeholders, kept and saved back. `.wxmx` read and write; no `.wxm`. | partial | `.wxm` and image cells: 3 |
| Evaluation queue | Splits cells into statements, `;` versus `$`, `:lisp` and `to_lisp()`, adds a missing terminator, one statement at a time | All of it, through MaximaKit (Phase 1). Cells run in order; Cmd+R evaluates all. | done | |
| Error handling | Optionally aborts on error, marks the failing statement and spot in the editor | The rest of the cell is skipped and the error shows with its text. The failing statement and the syntax error's spot are marked in the editor; see Error marker below. No abort-on-error setting yet. | partial | setting: 3 (step 14) |
| Questions and debugger | Answer cells for questions; the `(dbm:N)` debugger and LDB are special cases | Questions show inline with an answer field, and answers are saved the way wxMaxima saves them. The debugger prompt shows as a question; no debugger UI, no LDB. | partial | 3 |
| 2D math | Its own layout engine, selection and copy via `altCopy` | MathML through WebKit, rendered to images by one shared web view. Clicking an output gives a live, selectable view; long outputs break into lines (step 6). The context menu copies as Maxima input, LaTeX, MathML or a picture (step 7) | partial: see the second table | 3 |
| Plots | PNG or SVG from `img`, animations from `slide` | PNG and SVG plots (`wxplot_usesvg:true`), `wxdraw2d` (`wxdraw3d` not tried), read into the document at once; animations with play, pause and a frame slider (Phase 3 step 8) | done | |
| Autocomplete | `wxxml-symbols` and the user's own definitions | none | missing | 3 |
| Variables and status | Watch panel, status bar, CPU polling | Toolbar state (Ready, Evaluating…, waiting for an answer) and a status line for Maxima's own messages (`statusbar`, start-up problems). No watch panel. | partial | 3 |
| Help | Topic names, the HTML manual | none | missing | 3 |
| Export and tooling | HTML, LaTeX, `.mac`, `.wxm` export, undo, search, diff viewer | Undo for cell insert, delete, type changes and typing (also after a cell scrolled away). Find and Replace across every cell's input (Phase 3 step 3). No export, no diff. | partial | 3 |
| Settings | Maxima and gnuplot paths, display options, `wxmaxima-init` | The Maxima path. | partial | 3 |

## Found during Phase 2

| Feature | wxMaxima | Macsima now | Status | Phase |
| --- | --- | --- | --- | --- |
| Animations (`slide`) | Plays frame lists, with sliders | `with_slider`, `wxanimate`, `with_slider_draw` and animations in `.wxmx` files: the frames are read into the document; Play/Pause, a slider and the frame number; plays at `wxanimate_framerate` (the `fr` attribute), autoplays with `running="true"`. Saved back as wxMaxima writes them (Phase 3 step 8). No GIF export | done | GIF export: later |
| Copy math as Maxima input | Uses `altCopy` and its own text forms (each cell's `ToString`) | "Copy as Maxima Input" (Phase 3 step 7): a port of wxMaxima's `ToString`, using `altCopy`. Sums, products, integrals and limits come out quoted (`'sum(1/k^2,k,1,inf)`), one-sided limits as `plus`/`minus`, matrices as `matrix([..],[..])`. A test reads every output of ten fixtures back into Maxima and checks it equals the original | done | |
| Copy math as LaTeX and as a picture | Copy as LaTeX (each cell's `ToTeX`), MathML, RTF, bitmap, SVG | Copy as LaTeX: a translator over the same tree, following wxMaxima's `ToTeX` but plainer (`x^{2}`, `\pi`); every output of the glue and `.wxmx` fixtures compiles with LuaLaTeX (a test). Copy as Image: PNG and TIFF of the math alone. No RTF or SVG | done | RTF, SVG: later |
| Selecting whole cells; copy, cut, paste | Click or drag over cell brackets, Shift+arrows across cells; copies cells as `.wxm` (`text/x-wxmaxima-batch`), XML and text, pastes cells | Click a cell's gutter, Shift-click to extend, Shift+Up/Down past a cell's start or end, Select All Cells (Cmd+Shift+A). Copy, Cut, Paste, Delete (one undo step each). The pasteboard gets a `.wxmx` of the cells (outputs and images kept), `.wxm` text under wxMaxima's type and plain text; pasting reads either, also into an editor (Phase 3 step 7). No dragging across brackets; pasting between Macsima and wxMaxima untested | done | drag-select: later |
| Selecting text inside math | Directly in the worksheet | Click an output to swap in a live web view, then select | partial | 3 |
| Folded sections | Fold and unfold under headings | Folded cells from files are kept and saved back; a placeholder marks them. No folding in the editor. | missing | 3 |
| Hidden output (`hide`) | Hides a cell's output | Kept and saved back, not applied | missing | 3 |
| Text formatting in text cells | Bold, colours and more, stored on `line` | Kept while the text is unchanged; editing drops it; no formatting tools | missing | 3 |
| Box labels (`boxname`) | Shows the label | The box shows, the label doesn't | partial | 3 |
| Plot resolution | Uses `ppi` to show plots sharp | pngcairo plots are 600×450 at 1×, slightly soft on Retina; `ppi` is kept but not applied | partial | 3 |
| Matrix brackets | `bracketParens`, `angledParens`, `straightParens`, `noneParens`, round by default | All of them | done | |
| Dark mode | Configurable colours | Follows the system appearance: editor, syntax colours, bracket, find and error marks, the explanation marker, and the math images, which re-render when the appearance changes (the `appearance` key script, light and dark screenshots; Phase 3 step 5). Colours are not configurable | done | colour settings: later |
| Line breaking of long outputs | Breaks long expressions over lines at the window width, turning too-wide fractions and brackets into their linear form | The same approach (Phase 3 step 6): math wider than the output column breaks before `+`/`−` and after `=`, `,`, `:=`; a term wider than a line breaks between factors, with a `⋅` at the line end; too-wide fractions become `(a)/(b)`, roots `sqrt(a)`, brackets open up. Re-broken when the window is resized (after it settles). Matrices can't break and scroll sideways. Clicked (live) outputs break too | done | |
| Zoom | Saved in the file, applied | View › Zoom In (Cmd+plus, Cmd+=) and Zoom Out (Cmd+-) in 10% steps, 10% to 3200% as in wxMaxima, and Actual Size. Editor, gutter, outputs, plots and math scale; math is rendered again at the new size, so it stays sharp. Read from and saved to the file (Phase 3 step 5). No 80/120/150% presets | done | |
| Cursor position (`activecell`) | Saved and restored | Kept from the file, not updated | partial | 3 |
| Real keystrokes | | XCUITest target (`Tests/UITests/`, Phase 3 step 1) types real keys: Shift+Return, Cmd+1, Cmd+Z, Cmd+Shift+Delete. The key-script driver still posts synthesized events for the longer scripts. | done | |
| `.wxmx` timestamps | Local time | ZIPFoundation writes them two hours off here; harmless | partial | later |
| Answer layout | The answer follows the question on the same line | The same: the answer, or the field while Maxima waits, follows the question on its line (Phase 3 step 4) | done | |
| Error marker | 26.09: messages it can explain in yellow, with the explanation as a tooltip, and a red bracket on the failed cell (traced in Phase 3: this was the yellow seen on 03-errors). After 26.09: the failing statement and the syntax error's spot marked in the input | All of it: yellow marker with tooltip and a button showing the explanation (wxMaxima's texts), a red cell bar, the failing statement and the spot marked in light red until the cell is edited; an unbalanced bracket Macsima refuses to send is marked too (Phase 3 step 4). No "jump to error" command yet | done | jump to error: 3 |
| Input labels after opening a file | No `(%iN)` until the cell is evaluated again | The same: `-->` until the cell is evaluated; output labels show as saved (Phase 3 step 4) | done | |
| Syntax highlighting in code cells | Yes | Comments, strings, numbers, keywords, Lisp symbols and `:lisp` lines, terminators, and built-ins from `<wxxml-symbols>` (Phase 3 step 3). Single-letter names in that list (`x`, `a`, `t`, ...) are interned by Maxima's own code, so they stay plain | done | |
| Matching brackets | Highlights the partner of the bracket at the cursor | The bracket next to the caret and its partner get a background; brackets in strings and comments don't count (Phase 3 step 3) | done | |
| Auto-indent | Indents continuation lines | Return keeps the indentation, one level deeper after an open bracket; a closing bracket on an empty line takes a level off (Phase 3 step 3) | done | |
| Comment out a selection | Wraps the selection in `/* */` | Cmd+/ wraps the touched lines in one `/* */`, or unwraps them (Phase 3 step 3) | done | |
| Find and Replace | Across the worksheet | Across every cell's input, with match case, Replace and Replace All (one undo step); outputs are not searched (Phase 3 step 3) | done | |
| Moving between cells with the arrow keys | Up and Down move the cursor through inputs and outputs, across cells | Up on a cell's first line and Down on its last move to the neighbouring cell with an editor, in the same column (Phase 3 step 3). Outputs are skipped: they can't take the focus. Whole cells can be selected with Shift+Up/Down (step 7) | partial | outputs: to agree at checkpoint B |
| After Shift+Return | The cursor moves to the next cell, or to a new cell at the end | The same (a Phase 2 follow-up, 2026-10-19) | done | |
| Starting the app | Opens an untitled worksheet | The same; untitled worksheets are saved later with Cmd+S (a Phase 2 follow-up, 2026-10-19) | done | |
| Closing a window | Asks to save unsaved changes; stops that window's Maxima | Asks: a new worksheet gets macOS's Delete / Cancel / Save panel, a saved one Save / Revert Changes / Cancel (the app sets macOS's "ask to keep changes when closing", which a system-wide choice overrides). macOS autosave stays on. The window's Maxima stops when it closes, the others keep running (Phase 3 step 5) | done | |

## Math XML translator (WXMLKit)

Tags the translator doesn't know render as their text content (never dropped) and are listed here. Across the 679 math chunks in the `.wxmx` fixtures and all transcript chunks, `slide` was the only one; it is handled since Phase 3 step 8.

| Tag | Emitted by wxMathML.lisp for | Status |
| --- | --- | --- |
| `slide` | animations (`wxanimate`, `with_slider_draw`) | done (Phase 3 step 8) |
