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
| `.wxm` plain-text format | Opens as a worksheet (File › Open, Phase 3 step 13): cells, answers, hide, folds and image cells (caption, base64 image; images over 48 MB or unreadable are left out with a warning). Files over 64 MB are refused; UTF-8, else Latin-1. Also read for pasting cells | Saved as wxMaxima's TreeToWXM writes it, image cells included, when the document is a `.wxm` (Save, Save As, Duplicate). Like wxMaxima: no outputs and no zoom | full | Outputs are lost by design: save as `.wxmx` to keep them. Image cells in `.wxm` checked against wxMaxima's source, not against a wxMaxima-written file |

## Document

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| `wxMaximaDocument version` | yes; a warning above 1.5 | `1.5` | full | |
| `zoom` | yes, applied to the view | yes, the current zoom (View › Zoom In and Out) | full | |
| `activecell` | kept | written back unchanged (not updated from Macsima's focus) | partial | |
| `variables_num`, `variables_N` (watch list) | read: the variables panel's list (Phase 3 step 11); `variables_num` capped at 1000 | written as wxMaxima writes it: the count, the names, and one empty `variables_N` more (its grid's empty row, WXMXformat.cpp) | full | Format taken from wxMaxima's source; no wxMaxima-written file with a watch list among the fixtures yet |
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
| `cell type="pagebreak"` | yes, shown as a dashed rule | yes | full | |
| `cell type="image"` | yes: the caption is editable, the image (PNG, JPEG, GIF, SVG, `.svgz`) shown below; Cell › Insert Image… makes one | yes, as wxMaxima writes them (caption editor, then `img`); an image cell whose image is missing stays a kept raw cell | full | |
| Unknown cell types | kept as raw cells, warned | written back verbatim | partial | |
| `fold` (folded cells under a heading) | yes: the cells join the list after their heading, which shows folded; nested folds too | yes, a folded heading's section inside its `<fold>`; wxMaxima 26.09 reads it back (fixture `folded-resaved.wxmx`) | full | |
| `hide="true"` (hidden output) | yes: the cell shows its first line, outputs hidden | yes | full | |
| `hideToolTip` | kept | written back | full (kept) | |
| `questionN`/`answerN`, `auto_answer` (known answers) | kept, not used | written back | partial | |
| Unknown cell attributes and child elements | kept, warned | written back | full (kept) | |

## Editor text

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| `editor` with `line` elements, `&#x0A;` newlines | yes | one `line`, newlines as `&#x0A;` (as wxMaxima 26.09) | full | |
| Carriage returns (soft line breaks in older files) | yes, kept as `\r` | written as `&#x0D;` | partial: the editor shows them as real line breaks, wxMaxima reflows them | |
| Text formats (`bold`, `italic`, `underline`, `strikethrough`, `superscript`, `subscript` ranges on `line`; wxMaxima after 26.09, GH #492) | yes: shown and editable (Format menu), kept through typing and undo | yes, as wxMaxima writes them (ranges in code points from the text's start); 26.09 and older show the text plain | full | |
| Other line attributes, inline tags in `line` | kept while the cell's text is unchanged; editing the text drops them | the original `editor` XML while unchanged | partial | |
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
| `img` with `ppi`, `rect`, `maxWidth`, `gnuplotdata_gz`, ... | yes (PNG, JPEG, SVG); the attributes are kept | written back; the gnuplot data stays an attachment; Macsima's own plots carry `ppi="192"` | partial: `ppi` applied when showing (pixels × 72 / ppi points); `rect` and `maxWidth` not | |
| `slide` (animations) | yes: frames read from the archive, played with Play/Pause and a slider; `fr`, `running`, `frame` used; other attributes kept | yes, frames as `imageN.ext`, attributes as read (the shown frame and playing state are not saved yet) | partial | |
| Highlighting (`hl` boxes) | yes, as a box | written back | full | |
| `boxname` on `hl` | kept, not shown | written back | partial | |

## Saving

- **Autosave in place.** Macsima is a macOS document app: while you edit a worksheet that has a file, macOS saves it in the background, with Macsima's writer, into that same file. A `.wxmx` written by wxMaxima is therefore rewritten by Macsima as soon as you edit it, even before you press Cmd+S; everything in the tables above that is "kept" survives that. Closing asks to Save, Revert Changes (back to the version you opened) or Cancel, and File › Revert To lists older versions. Open a copy if the original must stay byte for byte as wxMaxima wrote it.

## Behaviour notes from the comparison with wxMaxima 26.09

- **Batch mode.** `wxmaxima -b` evaluates a file and saves it, but does not exit. It stops at errors and questions without saving. It also hangs on a `:lisp-quiet` line in a cell, because it waits for a prompt that never comes; Macsima fixed the same hang in Phase 2. Avoid `:lisp-quiet` in cells you want wxMaxima to evaluate in batch mode.
- **Empty code cells.** wxMaxima adds a `;` to an empty code cell's input when it evaluates it.
- **Escaping.** wxMaxima writes `'`, `"` and tab in text as `&apos;`, `&quot;` and `&#x09;`. Macsima writes them literally. Both are the same XML.
- **Plots.** wxMaxima re-plots on evaluation, so image bytes and sizes differ, and image entries can come in a different order. Neither app depends on that order.
