# Releases

Since 0.3, work is planned as features that ship in a release, not as phases. Each release lists its features
here while it is in progress; the release notes (`docs/RELEASING.md`) are written from this list. Gaps against
wxMaxima stay in `docs/PARITY.md`.

## 0.4 (in progress)

- **Selecting inside math** (done 2026-11-01). Click a symbol in an output to select it, click again for
  the part around it, or drag across terms or matrix entries; ⌘C copies the part as Maxima input, and the
  context menu copies it as LaTeX, MathML or an image. Outputs stay images: the renderer also measures
  where each part sits. Replaces the click-to-select live view. Details and gaps in `docs/PARITY.md`.

## 0.3 (2026-11-01)

The first shared release: a notarized DMG with Sparkle updates (`docs/PHASE4_REPORT.md`).
