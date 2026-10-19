# Phase 3 snapshots: line breaking (step 6)

- `01-before-760.png`: before. A window 760 points wide; long outputs run past its edge.
- `02-after-760.png`, `03-after-1100.png`: the same outputs broken at the window's width, then again after widening it.
  The 30-column matrix can't break; at 760 points it scrolls sideways.
- `04`–`13`: outputs from `Tests/Fixtures/transcripts/glue/33-long-outputs.txt`, each on one line (`before`) and
  broken for a 700-point row (`after-700`): a rational function, the roots of a cubic, an integral, a Taylor
  series, and a product (line ends show the multiplication dot).

Made with the `wrap-basics` key script and `macsima-render wrap <dir> 700`.
