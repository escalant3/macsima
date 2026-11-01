# Macsima manual

Macsima is a Mac front end for [Maxima](https://maxima.sourceforge.io), the computer algebra system. It opens and saves wxMaxima's worksheets, so you can move between the two. This manual describes Macsima as of the end of Phase 3 (October 2026). Where Macsima behaves differently from wxMaxima, a **wxMaxima:** note says so.

What Macsima needs: macOS 26 on Apple silicon, Maxima from Homebrew (`/opt/homebrew/bin/maxima`), and gnuplot for plots (`/opt/homebrew/bin/gnuplot`). Other paths can be set in Settings.

## Contents

1. [Worksheets and cells](#worksheets-and-cells)
2. [Writing code](#writing-code)
3. [Evaluating](#evaluating)
4. [Results: math, plots, animations](#results-math-plots-animations)
5. [Errors](#errors)
6. [Questions, the debugger and Lisp](#questions-the-debugger-and-lisp)
7. [Text, headings and structure](#text-headings-and-structure)
8. [Selecting, copying and pasting](#selecting-copying-and-pasting)
9. [Finding and replacing](#finding-and-replacing)
10. [The sidebar: contents, variables, manual](#the-sidebar-contents-variables-manual)
11. [The status bar](#the-status-bar)
12. [Files](#files)
13. [Export](#export)
14. [View: zoom and appearance](#view-zoom-and-appearance)
15. [Settings](#settings)
16. [Keyboard shortcuts](#keyboard-shortcuts)
17. [Things to know](#things-to-know)

## Worksheets and cells

A worksheet is a list of cells. Each window has its own worksheet and its own Maxima, which starts when the window opens and stops when it closes. A new worksheet starts with one empty code cell.

Kinds of cell:

| Cell | What it holds | Insert with |
| --- | --- | --- |
| Code | Maxima input, and its results below | ⌘0 |
| Text | Prose, with bold, italic and more | ⌘1 |
| Title | The worksheet's title | ⌘2 |
| Section | A section heading | ⌘3 |
| Subsection | A subsection heading | ⌘4 |
| Image | A picture with a caption | Cell › Insert Image… |

The new cell goes after the cell you are in. Files from wxMaxima can also hold subsubsections, two deeper heading levels and page breaks (a dashed line); Macsima shows and keeps them.

- **Change a cell's kind:** Cell › Change Cell Type.
- **Delete the cell you are in:** ⌘⇧⌫ (Cell › Delete Cell).
- **Move between cells:** ↑ on a cell's first line goes to the cell above, ↓ on its last line to the cell below, in the same column. Cells without text (images, page breaks) are skipped.
- **The bar on a cell's left** is blue for the cell you are in and red for a cell whose last run failed.

Undo (⌘Z) and Redo (⌘⇧Z) cover typing and every change to cells: inserting, deleting, changing kinds, pasting, Replace All. Undo still works for a cell that scrolled out of view.

## Writing code

Code cells colour Maxima's syntax: comments, strings, numbers, keywords (`if`, `for`, `do`, ...), Lisp symbols (`?car`) and `:lisp` lines, terminators (`;`, `$`), and the names Maxima knows. Single-letter names stay plain.

- **Matching brackets.** With the caret next to a bracket, it and its partner are highlighted. Brackets inside strings and comments don't count.
- **Indenting.** Return keeps the line's indentation, and adds a level after an open bracket. Typing a closing bracket on an empty line takes a level off.
- **Commenting out.** ⌘/ wraps the lines you are on in one `/* */`, or removes it.
- **Return** starts a new line. **⇧Return** evaluates (see [Evaluating](#evaluating)).

### Autocomplete

Press **Esc** in a code cell to complete the name you are typing. **⌃Space** (Cell › Complete Word, wxMaxima's key) does the same, unless macOS uses ⌃Space to switch input sources.

- If only one name fits, it is inserted at once.
- If several fit, a list opens under the caret. Keep typing to narrow it, choose with ↑ and ↓, and accept with Return or Tab (or a click). Esc closes it.
- The list holds:
  - every name Maxima knows;
  - the function templates wxMaxima ships (about 2,000), such as `integrate(expr, x)`;
  - the names used in your code cells, and the functions you defined with `f(x) := ...` or `define(...)`, marked "worksheet". Your own definition of a function replaces Maxima's template.

**Templates.** Choosing a template inserts it with its arguments as placeholders, for example `integrate(<expr>, <x>, <a>, <b>)`. The first placeholder is selected, so you type over it. **Tab** goes to the next placeholder and **⇧Tab** to the one before. Placeholders have a light blue background.

**Show Template** (⌃⇧Space) lists only the templates of the function name before the caret, for example the five forms of `diff`.

**wxMaxima:** Esc starts a Greek-letter sequence there (Esc `alp` Esc gives α). In Macsima Esc completes; Greek letters this way are not available yet.

## Evaluating

| Action | Keys |
| --- | --- |
| Evaluate the cell you are in, then go to the next cell (or a new one at the end) | ⇧Return |
| Evaluate all cells, in order | ⌘R |
| Interrupt the running computation | ⌘. (or the stop button in the toolbar) |
| Restart Maxima (all values and definitions are lost) | Maxima › Restart Maxima, or the arrow button |

Maxima runs one statement at a time. A cell may hold several statements, each ending in `;` (show the result) or `$` (don't). A missing terminator after the last statement is added for you. Input labels `(%i1)` and output labels `(%o1)` show in the left margin.

The toolbar shows Maxima's state: Starting, Ready, Evaluating…, Waiting for an answer, In the debugger, Lisp mode.

**Abort on error** (Settings, on by default). When a statement fails, the rest of its cell and the cells waiting after it are not run. Turn it off and everything goes on after an error.

A waiting cell, or one not run after an error, keeps its old results until it runs.

After opening a file, code cells show `-->` instead of a label until they are evaluated again, as in wxMaxima.

## Results: math, plots, animations

Results show as typeset math. Long results break into lines at the window's width: before `+` and `−`, after `=` and `,`. A fraction or root too wide for a line is written in its linear form, `(a)/(b)`. A matrix too wide for the window scrolls sideways (swipe, or ⇧ and the scroll wheel). Results break again when you resize the window.

- **Selecting inside math.** Click a symbol in a result to select it; click it again to select the part around it, and again for the next larger part. Drag across a result to select the terms you cover, or a block of a matrix's entries. ⌘C copies the selection as Maxima input; Esc selects the part around it, and from a whole result goes back to the cell's input.
- **Results with the keyboard.** ↓ at the end of an input selects the cell's first result, then each printed message, error and result in turn, then the next cell's input; ↑ goes back the same way. On a selected result, Return goes into its parts (a sum's terms, a fraction's numerator and denominator, a matrix's entries), ← and → move between parts, ⇧← and ⇧→ select several neighbouring parts, and Esc goes back out. In a matrix the four arrows move between entries and ⇧ with an arrow selects a block. ⌘C copies what is selected; on an error, that is its message. Settings › Worksheet › Arrow keys skip output brings back ↑ and ↓ going from input to input.
- **Copying a result.** Right-click a result (with part of it selected, the menu copies that part):
  - Copy as Maxima Input: text you can paste into a cell, for example `'sum(1/k^2,k,1,inf)`;
  - Copy as LaTeX: for example `\sum_{k = 1}^{\infty} \frac{1}{{k}^{2}}`;
  - Copy MathML;
  - Copy as Image: PNG and TIFF of the math alone.
- **Boxes.** `box(expr)` draws a box. `box(expr, name)` shows the name small above it. `box(expr, highlight)` shows the expression in red, without a box.

**Plots.** `wxplot2d`, `wxplot3d`, `wxdraw2d` and the other `wx...` commands show the plot inside the worksheet. Choose PNG or SVG in Settings, or with `wxplot_usesvg: true$`. PNG plots are drawn at twice their size, so they are sharp on a Retina screen. `wxdraw` plots are not, yet. Plots are part of the worksheet: they survive restarts and are saved in the file.

**Animations.** `with_slider`, `wxanimate` and `with_slider_draw` show an animation with Play/Pause, a slider and the frame number. It plays at `wxanimate_framerate`.

## Errors

When a statement fails, Macsima shows Maxima's message under the cell. It also marks the failing statement in the input in light red, and for a syntax error the spot where Maxima's parser stopped in a darker red. The marks stay until you edit the cell.

- **Explanations.** A yellow message has an explanation, taken from wxMaxima. Hover over it, or click the light bulb.
- **Unbalanced brackets.** A cell whose brackets don't match is not sent to Maxima at all. The unmatched bracket is marked instead.
- **Go to Next Error** (⌘') and **Go to Previous Error** (⌘⇧") go from cell to cell through the worksheet's errors, round the end, with the failing statement selected.

## Questions, the debugger and Lisp

**Questions.** When Maxima asks something (`asksign`, `integrate` with an unknown sign), the question shows under the cell with a field on the same line. Type the answer (`pos`, `yes`, ...) and press Return; the `;` is added for you. The answer is saved with the worksheet. Interrupt (⌘.) while a question waits stops the cell.

**The debugger.** When Maxima enters its debugger (`(dbm:1)`), the prompt shows with:

- a field for a break command (`:bt`, `:next`, `:break f 2`, ...) or any expression, evaluated in the current frame;
- buttons for Step Over, Step Into, Continue, Backtrace, Leave Level and Stop;
- where Maxima stopped, when the function came from a file: the file, the line, and that line's text.

The Maxima menu has the same commands with Xcode's keys:

| Command | Keys |
| --- | --- |
| Step Over (`:next`) | F6 |
| Step Into (`:step`) | F7 |
| Continue (`:resume`) | ⌃⌘Y |
| Show Backtrace (`:bt`) | |
| Leave Debugger (`:top`) | |

**Debug on Error** (Maxima menu) turns on `debugmode`, so an error stops in the debugger instead of ending the cell.

Breakpoints need functions loaded from a file: Maxima keeps no line numbers for functions typed into a cell. For example:

```maxima
batchload("myfunctions.mac")$
:break f 1
f(3);
```

**Lisp mode.** `to_lisp();` switches Maxima to Lisp. Cells are then read as Lisp forms and get no input labels, and the status bar says "Lisp mode". Return to Maxima with the status bar's button, the Maxima menu, or by evaluating `(to-maxima)`.

## Text, headings and structure

**Text cells** hold prose. In the Format menu:

| Format | Keys |
| --- | --- |
| Bold | ⌘B |
| Italic | ⌘I |
| Underline | ⌘U |
| Strikethrough | |
| Superscript | ⌃⌘= |
| Subscript | ⌃⌘- |

Typing continues the format before the caret. Pasting brings plain text.

**Folding.** A heading with cells under it has a triangle in its margin: click it to fold the section, up to the next heading of the same or a higher level, and "N cells folded" shows in its place. Other ways to fold:
- Cell › Fold or Unfold Section;
- Fold All (⌘⌥[) and Unfold All (⌘⌥]).

Moving with the arrow keys skips folded cells. Find, Go to Error and the contents panel unfold what they need. Folds are saved in the file.

**Hiding a cell.** Cell › Hide or Show Cell (or the triangle that appears on hover) shows a code or text cell as its first line, with its results hidden.

**Image cells.** Cell › Insert Image… adds a picture (PNG, JPEG, GIF, SVG, TIFF) with a caption you can edit.

## Selecting, copying and pasting

Inside a cell, text selects and copies as in any Mac app.

To work with **whole cells**:
- Click a cell's left margin to select it; ⇧-click another to extend the selection.
- Or press ⇧↑ at the start of a cell, or ⇧↓ at its end, to go on selecting whole cells.
- Select All Cells: ⌘⇧A.

Then:
- Copy (⌘C), Cut (⌘X) or Delete (⌫) the selected cells, each one undo step.
- Paste (⌘V) inserts copied cells after the cell you are in, with their results, plots and images.
- The clipboard also carries the cells in wxMaxima's `.wxm` form, and Macsima pastes cells copied in wxMaxima. Pasting between the two apps hasn't been tested yet.

## Finding and replacing

**⌘F** opens the find bar above the worksheet. It searches the input of every cell, not the results.
- **Next and previous match:** ⌘G and ⌘⇧G, round the end.
- **Find the selection:** ⌘E.
- **Replace:** ⌘⌥F shows the replace field. Replace changes the current match, and Replace All changes every match in one undo step.
- **Match case** is an option in the bar.
- **Close:** Esc closes the bar.

## The sidebar: contents, variables, manual

The sidebar on the right has three panels. ⌘⌥0 shows or hides it. View › Contents (⌘⌥1), Variables (⌘⌥2) and Manual (⌘⌥3) open a panel, or hide the sidebar when that panel is already showing.

**Contents** lists the worksheet's headings, indented by level. The section the cursor is in is highlighted, and folded headings have a small arrow. Click a heading to go there; folded sections around it open.

**Variables** watches values.
- **Adding names.** Type names into the field (separated by spaces or commas), or click Add All for every variable that has a value.
- **What it shows.** After each evaluation the values are updated. A value is shown in Maxima's linear form, cut at 4,000 characters. A function shows its definition (`f(t):=t^2`), and a name without a value says "no value".
- **Right-click** for Copy Value or Stop Watching; ⌫ removes the selected name.
- **Saved.** The list is saved in the file, where wxMaxima reads it too.

**Manual** shows Maxima's manual, the text `describe` prints.
- **F1** looks up the name or operator at the caret, or the selected text. Right-click in a code cell for Look Up "…" in Maxima Manual.
- **Matches:** every entry with that name is shown (`diff` has three), with its section.
- **Links:** names the manual mentions are links. Related topics are listed at the end.
- **Moving around:** Back returns to the previous topic, and the search field looks up any topic.
- **While Maxima works:** lookups wait until Maxima is idle.

## The status bar

The bar at the bottom shows:

- **on the left:** Maxima's own messages (what `wxstatusbar` prints, progress text while plotting, start-up problems), and a note with a Return to Maxima button in Lisp mode;
- **on the right:** while Maxima works, the time since it started and its CPU use (100% is one core); afterwards, how long the last evaluation took.

## Files

Macsima opens and saves wxMaxima's two formats:

- **`.wxmx`** (the default) keeps everything: cells, results, plots, folds, text formats, zoom, the watched variables and the cursor position. Parts of a file Macsima does not understand are kept and written back unchanged. When a file has such parts, a banner says so when it opens.
- **`.wxm`** is plain text: inputs, headings, text, images and answers, but no results (as in wxMaxima).

**Opening and saving.**
- **Open:** File › Open, or drag a file onto Macsima. Macsima is not the default app for these files; wxMaxima stays the default.
- **Save:** ⌘S. Save As, Duplicate and Revert are in the File menu as usual, and File › Open Recent lists recent files.
- **Where the cursor goes:** a file opens with the cursor in the cell where it was saved, also for files from wxMaxima.

**Autosave.** Like other Mac apps, Macsima saves a worksheet that has a file in the background while you edit it. A `.wxmx` written by wxMaxima is therefore rewritten by Macsima as soon as you change it. Open a copy if the original must stay exactly as wxMaxima wrote it. File › Revert To lists earlier versions.

**Closing** a window with unsaved changes asks:
- for a new worksheet: Delete, Cancel or Save;
- for a saved one: Save, Revert Changes or Cancel.

## Export

File › Export:

- **HTML…**: one file with your inputs, results as MathML, and plots and images inside it. It opens in any current browser and adapts to dark mode. An animation shows as its first frame.
- **LaTeX…**: a `.tex` file, plus a folder `name_img` beside it for the plots and images. It is tested with LuaLaTeX, and written to work with pdfLaTeX and XeLaTeX too.
- **Maxima Batch File…**: a `.mac` with your code, and text cells as comments. Maxima can `batch` or `load` it.

Maxima can export too: `wxworksheettohtml("notes.html")$` in a cell writes the page. Its options (`flavor`, `wxmx`) are not applied yet.

## View: zoom and appearance

| Action | Keys |
| --- | --- |
| Zoom In | ⌘+ or ⌘= |
| Zoom Out | ⌘- |
| Actual Size | View › Actual Size |

Zoom goes in 10% steps from 10% to 3200%. Math is drawn again at the new size, so it stays sharp. The zoom is saved in the file.

Macsima follows macOS's light or dark appearance: the editor, its colours and the math all change.

## Settings

Macsima › Settings (⌘,):

**Maxima**
- **Maxima and gnuplot.** Where the programs are, with Choose… and a check that they are there. These apply when a Maxima starts or restarts.
- **Abort on error.** See [Evaluating](#evaluating). Applies to open worksheets at once.
- **Plots: PNG or SVG.** Applies to open worksheets at once.

**Worksheet**
- **Code font and size.** The system's monospaced font by default.
- **Text size.** Headings keep their proportion to it.
- **Math size.** 16 by default.
- **Zoom for new worksheets.**

Font changes show at once; the worksheet's zoom comes on top.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| ⇧Return | Evaluate the cell, go to the next |
| ⌘R | Evaluate all cells |
| ⌘. | Interrupt |
| ⌘0 ⌘1 ⌘2 ⌘3 ⌘4 | Insert a code, text, title, section or subsection cell |
| ⌘⇧⌫ | Delete the cell |
| ⌘⇧A | Select all cells |
| Esc or ⌃Space | Complete the name |
| ⌃⇧Space | Show the function's templates |
| Tab, ⇧Tab | Next and previous template placeholder |
| ⌘/ | Comment or uncomment lines |
| ⌘' and ⌘⇧" | Go to the next and previous error |
| ⌘⌥[ and ⌘⌥] | Fold all, unfold all |
| ⌘F, ⌘⌥F | Find, Find and Replace |
| ⌘G, ⌘⇧G, ⌘E | Next, previous match; find the selection |
| F1 | Look up the name at the caret in Maxima's manual |
| ⌘⌥0 | Show or hide the sidebar |
| ⌘⌥1, ⌘⌥2, ⌘⌥3 | Contents, Variables, Manual |
| F6, F7, ⌃⌘Y | Debugger: step over, step into, continue |
| ⌘B ⌘I ⌘U | Bold, italic, underline (text cells) |
| ⌃⌘= and ⌃⌘- | Superscript, subscript (text cells) |
| ⌘+ ⌘- | Zoom in, zoom out |
| ↑ and ↓ | At a cell's first or last line: to the cell above or below |

## Things to know

- **Your `maxima-init.mac` is used.** Macsima's Maxima reads `~/.maxima/maxima-init.mac` like any Maxima.
- **Each window has its own Maxima.** Values defined in one window are not seen in another.
- **wxMaxima behaviour that's still missing:**
  - Greek letters with Esc sequences.
  - Selecting across several results at once.
  - Arrow keys that stop on results.
  - Completing file names in `load("...")`.
  - A breakpoint margin.
  - Colour settings.
  - A diff viewer.

  The full list, with what is planned when, is in `docs/PARITY.md`.
- **For files you share with wxMaxima,** `docs/WXMX_COMPAT.md` lists exactly what each format keeps.
