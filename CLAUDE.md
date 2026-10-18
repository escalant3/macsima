# Macsima

A native macOS front end for Maxima, written in Swift, as a personal tool. It does what wxMaxima does (long-term goal: 1:1 feature parity, reached in stages) with a better UI, and without wxWidgets or its dependencies.

Read `docs/BOOTSTRAP.md` before any work. Its wire protocol reference and roadmap are the plan. If the code and the doc disagree, tell me and update the doc.

## Decisions (already made, do not reopen)
- Personal tool first. Sharing is optional later. No packaging, DMG, notarization, bundling or sandboxing work unless I ask.
- Engine: SBCL only. Baseline is Homebrew Maxima 5.50.0 at `/opt/homebrew/bin/maxima`, gnuplot from Homebrew. Never bundle or modify Maxima.
- Platform: arm64 only, macOS 26 (Tahoe) minimum, current Swift and SwiftUI APIs. Ease of coding beats backward compatibility. AppKit is fine where SwiftUI falls short. No UIKit.
- License: GPL-2.0-or-later. Every source file starts with `// SPDX-License-Identifier: GPL-2.0-or-later`. When porting from wxMaxima (including wxMathML.lisp), keep its copyright notices and say so in a comment.
- File format: full `.wxmx` compatibility is the long-term goal. At first, opening files this app wrote is enough. Record every unsupported element or feature in `docs/WXMX_COMPAT.md` (element, read, write, status, what to avoid in wxMaxima). Never silently drop data when reading a file: keep unknown XML, warn on open, write it back where possible.
- Feature parity with wxMaxima is the target, staged by the MVP column in BOOTSTRAP.md. Track gaps, do not hide them.

## Working rules
- Verify protocol claims against a real Maxima process before relying on them. Save captured output under `Tests/Fixtures/transcripts/`.
- Swift Package Manager layout from BOOTSTRAP.md: `MaximaKit` (no UI), `WXMLKit`, `WorksheetKit`, then the app target. Keep the engine testable without a window.
- Swift 6 language mode, strict concurrency. Use an actor for the Maxima session.
- Do not claim something works unless you built and ran it. Say what you could not test.
- Treat `.wxmx` files as untrusted input (size caps on decompression).
- Small commits, one topic each.

## Commands
- Build and test: `swift build`, `swift test`
- Maxima: `/opt/homebrew/bin/maxima --version`
- Does my SBCL have threads: `sbcl --noinform --eval '(progn (format t "threads: ~a~%" (if (member :sb-thread *features*) "yes" "no")) (quit))'`

## Current phase
Phase 0 only. See `docs/PHASE0_PROMPT.md`. Stop and ask before starting Phase 1.
