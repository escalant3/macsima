# .wxmx compatibility ledger

What Macsima reads and writes compared with wxMaxima, as of Phase 2 (2026-10-18). One row per element or
feature.
- **Read** means the app understands the element and shows it.
- **Kept** means it is not shown but is preserved in the model and written back unchanged on save. A banner lists such things when the file opens.
- **Status** is full, partial or missing.

**Sources.** wxMaxima's writer and reader at commit 13e4aee (`src/WXMXformat.cpp`, `src/cells/GroupCell.cpp`, `src/cells/EditorCell.cpp`, `src/MathParser.cpp`), the manual's file-format section, files the installed wxMaxima 26.09.0 wrote in batch mode, and the 13 sample files from wxMaxima's repository in `Tests/Fixtures/wxmx/wxmaxima-samples/`.

**Checked by tests:**
- every readable sample, and every wxMaxima-written file, survives read → write → read unchanged;
- ten Macsima sessions (`Tests/Fixtures/wxmx/macsima-written/`) reopen and re-evaluate to the same results;
- wxMaxima 26.09.0 loads, evaluates and re-saves eight of them;
- Macsima reads each of those re-saves, and they match the originals cell by cell.

## Container

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| Zip container, no compression | yes (stored or deflated) | yes, stored, in wxMaxima's order: `mimetype`, `format.txt`, `content.xml`, then images | full | |
| `mimetype` = `text/x-wxmathml` | yes; a warning if missing or different | yes | full | |
| `format.txt` | ignored | yes, Macsima's own short text | full | |
| `content.xml` header comment | ignored | `Created using Macsima` | full | |
| Image entries (`imageN.png`, `.jpg`, ...) | yes, read into the model when an output uses them | yes; numbered so they never clash with kept files | full | |
| Other archive files (images of kept cells, animation frames, gnuplot data `.gz`) | kept as attachments | written back under the same name | full (kept) | |
| Untrusted input | caps: `content.xml` 64 MB, any file 128 MB, total 512 MB, 10,000 files; `..`, absolute and backslash paths rejected; XML nested deeper than 512 levels rejected | | full | |
| Zip timestamps | | ZIPFoundation 0.9.19 writes them two hours off from local time here (looks like UTC); harmless, wxMaxima ignores them | partial | |
| `.wxm` plain-text format | no | no | missing (out of scope for Phase 2) | Save as `.wxmx` |

## Document

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| `wxMaximaDocument version` | yes; a warning above 1.5 | `1.5` | full | |
| `zoom` | kept in the model (not applied to the view) | yes, unchanged | partial | |
| `activecell` | kept | written back unchanged (not updated from Macsima's focus) | partial | |
| `variables_num`, `variables_N` (watch list) | kept | written back | full (kept) | |
| Unknown document attributes | kept, warned | written back | full (kept) | |
| Unknown document-level elements | kept, warned | written back at the end of the document | partial: position not preserved | |

## Cells

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| `cell uuid` | yes, becomes the cell's ID | yes (lowercase, as wxMaxima) | full | |
| `cell type="code"` with `input` and `output` | yes | yes | full | |
| `cell type="text"` | yes | yes | full | |
| `title`, `section`, `subsection` (`sectioning_level` 1, 2, 3) | yes | yes | full | |
| `subsection` with `sectioning_level` 4, 5, 6 (subsubsection, heading 5, heading 6) | yes | yes, the way wxMaxima writes them | full | |
| `cell type="subsubsection"` (older files) | yes | written as `subsection` level 4 | full | |
| `cell type="pagebreak"` | yes, shown as a placeholder | yes | full | |
| `cell type="image"` | kept (shown as a placeholder) | written back verbatim with its image | partial | Image cells |
| Unknown cell types | kept as raw cells, warned | written back verbatim | partial | |
| `fold` (folded cells under a heading) | kept, not shown; a placeholder says so | written back | partial | Folding sections you want to edit in Macsima |
| `hide="true"` (hidden output) | kept, not applied | written back | partial | Hiding cells |
| `hideToolTip` | kept | written back | full (kept) | |
| `questionN`/`answerN`, `auto_answer` (known answers) | kept, not used | written back | partial | |
| Unknown cell attributes and child elements | kept, warned | written back | full (kept) | |

## Editor text

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| `editor` with `line` elements, `&#x0A;` newlines | yes | one `line`, newlines as `&#x0A;` (as wxMaxima 26.09) | full | |
| Carriage returns (soft line breaks in older files) | yes, kept as `\r` | written as `&#x0D;` | partial: the editor shows them as real line breaks, wxMaxima reflows them | |
| Line formatting attributes (bold, colours in text cells) | kept while the cell's text is unchanged; editing the text drops the formatting | the original `editor` XML while unchanged | partial | Formatting text cells you want to edit in Macsima |
| Answers to questions (`editor type="input"` inside an output) | yes, shown under the question | yes, the same way | full | |

## Output

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| `output` / `mth`, split at `breakline` and at labels | yes | yes, `breakline="true"` on each output's first element | full | |
| Glue math tags (`mi`, `mn`, `mfrac`, ...) | yes | yes (Macsima stores Maxima's own XML) | full | |
| wxMaxima's saved dialect (`r`, `v`, `n`, `f`, `e`, `i`, `limit`, `fnm` operators, `ie` with `pos`) | yes | written back as read | full | |
| `lbl` with `altCopy` | yes | Macsima's own outputs keep the glue's `altCopy="%oN"`; wxMaxima writes `(%oN)` plus a tab | full | |
| Empty results (`(%oN)` with nothing after it) | yes, shown as the label | yes | full | |
| `t type="error"` | yes | yes, plus `errorkind` (maxima, syntax, lisp, interrupted), which wxMaxima keeps as an unknown attribute | full | |
| `t type="ASCII-Art"` (plain-text output, `display2d:false`, `tex()`) | yes, monospaced | yes; one element per output, where wxMaxima writes one per line | full | |
| `t` without a type, `type="warning"`, `type="Operator"` | as math (rendered as text) | written back | partial | |
| `img` with `ppi`, `rect`, `maxWidth`, `gnuplotdata_gz`, ... | yes (image); the attributes are kept | written back; the gnuplot data stays an attachment | partial: `ppi` and size not applied when showing | |
| `slide` (animations) | kept; shows the frame file names as text | written back with its frames | missing | Animations (`wxanimate`, `with_slider_draw`) |
| Highlighting (`hl` boxes) | yes, as a box | written back | full | |
| `boxname` on `hl` | kept, not shown | written back | partial | |

## Behaviour notes from the comparison with wxMaxima 26.09

- **Batch mode.** `wxmaxima -b` evaluates a file and saves it, but does not exit. It stops at errors and questions without saving. It also hangs on a `:lisp-quiet` line in a cell, because it waits for a prompt that never comes; Macsima fixed the same hang in Phase 2. Avoid `:lisp-quiet` in cells you want wxMaxima to evaluate in batch mode.
- **Empty code cells.** wxMaxima adds a `;` to an empty code cell's input when it evaluates it.
- **Escaping.** wxMaxima writes `'`, `"` and tab in text as `&apos;`, `&quot;` and `&#x09;`. Macsima writes them literally. Both are the same XML.
- **Plots.** wxMaxima re-plots on evaluation, so image bytes and sizes differ, and image entries can come in a different order. Neither app depends on that order.
