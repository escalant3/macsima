# .wxmx compatibility ledger

What this app reads and writes compared with wxMaxima. One row per element or feature. Status is
full, partial or missing. Nothing is implemented yet (Phase 0), so every row is missing. Unknown XML
must be kept, warned about on open and written back where possible (see CLAUDE.md).

| Element / feature | Read | Write | Status | Avoid in wxMaxima |
| --- | --- | --- | --- | --- |
| Zip container (`content.xml`, `mimetype`, images) | no | no | missing | |
| `wxMaximaDocument` root (`version`, `zoom`) | no | no | missing | |
| `cell type="code"` (`editor type="input"`, `output`) | no | no | missing | |
| `cell type="text"` | no | no | missing | |
| `cell type="title"`, `section`, `subsection`, `subsubsection`, `heading5`, `heading6` | no | no | missing | |
| `cell type="image"` | no | no | missing | |
| `cell type="pagebreak"` | no | no | missing | |
| Folded (hidden) cells | no | no | missing | |
| Embedded plot images and animations (`slide`) | no | no | missing | |
| `.wxm` plain-text format | no | no | missing | |

To seed from wxMaxima's manual (file format section) and sample worksheets in `Tests/Fixtures/wxmx/`.
