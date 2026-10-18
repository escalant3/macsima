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
- Build: `swift build`
- Test: `swift test`. The "Executed 0 tests" line is the XCTest runner and is expected when a package only uses Swift Testing. Read the Swift Testing line instead ("Test run with N tests ... passed") and check that N is above zero.
- Package platform must be `.macOS(.v26)` in `Package.swift`.
- Maxima: `/opt/homebrew/bin/maxima --version`
- Does my SBCL have threads: `sbcl --noinform --eval '(progn (format t "threads: ~a~%" (if (member :sb-thread *features*) "yes" "no")) (quit))'`

## Current phase
Phase 1 is done: `MaximaKit` is the tested engine (see `docs/PHASE1_REPORT.md`; Phase 0 findings are in `docs/PHASE0_REPORT.md`). Phase 2 (minimal worksheet) is next. Stop and ask before starting it.

Engine facts to keep in mind (details in the reports, BOOTSTRAP.md and fixtures):
- Use `MaximaSession` (an actor) for everything Maxima: `start`, `evaluate(cellID:text:)` returns an `AsyncStream<CellEvent>` ending in `.finished`, `answer`, `interrupt`, `restart`, `kill`, `shutdown`. Session-wide output arrives on `session.events`.
- Most engine tests replay `Tests/Fixtures/transcripts/glue/` through `ReplayTransport`; real-Maxima tests are skipped when `/opt/homebrew/bin/maxima` is missing. Record new behaviour by running `maxima-spike record` for just the new scenario.
- Errors are recognized from plain text only (`OutputClassifier.swift` lists the strings). An `error()` with an expression has its message in a `math` chunk.
- Each Maxima gets a private temp folder that is deleted on kill, restart and shutdown, along with any plot images in it. Load images as soon as they arrive.
- The exit test is `.build/debug/maxima-session Tests/Fixtures/scripts/phase1-exit.mxs`.
