# Phase 3 screenshots

Window-only captures (`screencapture -l`) taken by the key scripts in `Tests/Fixtures/keyscripts/`.

## Checkpoint A: the editor

| File | What it shows | Script |
| --- | --- | --- |
| `01-light.png` | Syntax colours, math, a matrix, an error with its explanation marker, a question answered on its line, text and title cells | `appearance` |
| `02-dark.png` | The same worksheet in dark mode | `appearance` |
| `03-bracket-match.png` | The caret after `)`: it and the `(` of `block` are marked | `checkpoint-a` |
| `04-find.png` | Cmd+F, `x`: 7 matches in three cells, the first selected | `checkpoint-a` |
| `05-error-marks.png` | The failing statement `b:1/0;` and the syntax error's spot `,,` marked in the input; explanation markers; an unbalanced `(` Macsima refused to send | `errors-basics` |
| `06-question-waiting.png` | The answer field on the question's line while Maxima waits | `eval-basics` |
| `07-zoom-150.png` | A saved worksheet at 150% | `zoom-basics` |
| `08-close-edited.png` | Closing an edited saved worksheet: Save, Revert Changes, Cancel | `close-saved` |

## Checkpoint B: math output

Before-and-after snapshots of line breaking are in `docs/phase3-snapshots/`.

| File | What it shows | Script |
| --- | --- | --- |
| `09-part-b.png` | A long expansion broken into lines, a `with_slider` animation with Play, the slider and the frame number, bold text, a folded section, an image cell | `checkpoint-b` |
| `10-cells-selected.png` | Two whole cells selected (gutter click, Shift-click), ready for Copy, Cut or Delete | `checkpoint-b` |
| `11-image-cell.png` | The image cell from wxMaxima's `all-celltypes` sample: caption and JPEG | `kinds-basics` |
| `12-folded.png` | Two sections folded with Fold All; "3 cells folded" | `folds-basics` |
| `13-text-formats.png` | Italic text with an underlined superscript (Format menu) | `format-basics` |
| `14-wxdraw-svg.png` | A `wxdraw2d` plot, then an SVG plot (`wxplot_usesvg:true`) | `plots-basics` |

## Checkpoint C: the Maxima side

| File | What it shows | Script |
| --- | --- | --- |
| `15-completion.png` | Esc after `integ`: the completion list, names and templates, arguments in grey | `complete-basics` |
| `16-template.png` | `integrate(<expr>, <x>, <a>, <b>)` inserted, `<expr>` selected; Tab goes on to `<x>` | `complete-basics` |
| `17-manual.png` | F1 on `integrate`: the manual's entry in the sidebar, prose rewrapped, references as links | `help-basics` |
| `18-variables.png` | The variables panel watching `x` and `f`, after evaluating | `panels-basics` |
| `19-contents.png` | The contents panel; Intro, where the focus is, marked | `panels-basics` |
| `20-status-bar.png` | The status bar while a loop runs: 3.0 s, CPU 100% | `panels-basics` |
| `21-debugger.png` | An interrupted question; a debugmode error in the debugger (`x`, `:bt`, `:top`); a breakpoint in `debug-f.mac` with the controls and the stop's file, line and source | `modes-basics` |
| `22-lisp-mode.png` | After `to_lisp()`: a Lisp cell without a label, the status bar's note and Return to Maxima | `modes-basics` |
| `23-export-html.png` | File › Export › HTML, opened in WebKit: inputs, MathML, the plot | `files-basics` |
| `24-settings.png` | The Settings window, Maxima tab (the scripts' own settings store) | `settings-basics` |
| `25-fonts.png` | Code font Menlo 20 and math size 30 from Settings, applied at once | `settings-basics` |
