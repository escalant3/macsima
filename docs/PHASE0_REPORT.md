# Phase 0 report: Maxima integration spike

2026-10-18 · macOS 26.5.1 (arm64) · Swift 6.3.3 (Command Line Tools, no Xcode) · Homebrew Maxima 5.50.0 (revision 2) on SBCL 2.6.9 · gnuplot from Homebrew

**Result: the exit criterion is met.** The spike (`Sources/maxima-spike`) listens on 127.0.0.1, spawns `/opt/homebrew/bin/maxima -s <port>`, accepts the connection and gets `- cos(x)` for `integrate(sin(x), x);`. With wxMathML.lisp loaded the same result arrives as tagged XML, the auth token is echoed, and the interrupt channel works on this SBCL.

## Checks

| Check | Result |
| --- | --- |
| `maxima --version` | `Maxima 5.50.0` |
| SBCL thread check (CLAUDE.md) | `threads: yes` |
| Glue reports `*wx-interrupt-channel-available*` | `true` |
| Interrupt channel (`interrupt` on the second socket) | Stopped a long `integrate`; Maxima printed `User interrupt` and returned to `(%i2)` |
| SIGINT to the process group | Stopped the same `integrate`; printed `Interactive interrupt at #x...` and returned to `(%i2)` |
| `float(%pi)`, `float(x)`, `float(1/3)` (ARM64 risk) | `3.141592653589793`, `x`, `0.3333333333333333` |
| `swift build` | Passes, no warnings |
| `swift test` | 1 test passes, but only with an extra flag (see below) |

## What worked

- **Raw link.** Bind, spawn, accept, send, read. Maxima connected over IPv4 within about 0.5 s.
- **Glue Lisp.** `Resources/lisp/wxMathML.lisp` (wxMaxima commit 13e4aee, unmodified, notices kept) is sent as one `:lisp-quiet` line, framed the way wxMaxima frames it. It loads in about 1 s and prints `<wxxml-key>`, `<wxxml-symbols>` and `<variables>`.
- **Transcripts.** 24 scenarios raw and 25 with the glue under `Tests/Fixtures/transcripts/` (index in its README). They cover a plain result, `$`, three kinds of error, two `asksign` questions, both interrupt paths, `plot2d`/`wxplot2d`, `:lisp`, `display2d:false`, `tex()` and `quit()`. Re-record them with `record.sh`.
- **Cleanup.** `killpg` with SIGTERM on exit left no Maxima or gnuplot processes, and no `maxout*` files in the temp folder.

## What differed from BOOTSTRAP.md (the doc is updated)

1. **Name.** The layout said `MaximaMac`; the repo uses `Macsima` (`App/Macsima/`).
2. **The sketch did not survive strict concurrency.** It was rewritten: one serial queue, an explicit 127.0.0.1 bind, and `posix_spawn` with `POSIX_SPAWN_SETPGROUP`. Homebrew's `maxima` script `exec`s SBCL, so the PID we spawn is the Lisp itself.
3. **Extra output before the banner.** The socket starts with `pid=N`. Maxima prints `Connecting Maxima to server on port N` to its own stdout, not to the socket. The user's `~/.maxima/maxima-init.mac` is loaded and announced in the banner.
4. **How the glue is sent.** wxMaxima strips comments and indentation and joins the file into one line (about 88 KB). None of the setup lines gets a prompt back, so the app must not wait for one after setup.
5. **`math`, not `mth`.** 5.50.0 with the current glue emits `<math>` only.
6. **Inner tags have attributes.** Seen: `lisp="..."` on most tags, plus `altCopy`, `bracketParens`, `list` and `listdelim`. The top-level tags (`PROMPT`, `math`, `variables`, ...) still have none, so the "trivial scanner" plan holds.
7. **No `del="yes"` on the `wxplot2d` image.** The output was `<img lisp="wxxml-tag">/var/folders/.../maxout_N_1_M.png</img>`, in a `math` chunk labelled `%t1`.
8. **Not all output is XML.** Errors, `print` side output, `tex()` and everything under `display2d:false` arrive as plain text between tags. The scanner's "miscellaneous output" path is a main path, not an edge case.
9. **Prompt details.**
   - A syntax error and a `:lisp` line don't advance the input label.
   - After `:lisp` the prompt is `(%i1)` with no trailing space.
   - In glue mode a question arrives as `<PROMPT><math>...</math></PROMPT>`. In raw mode it has no marker, so only silence tells you a question is waiting.

## What changes the plan

- **Phase 1 can rely on the interrupt channel.** Threads are on, so interrupting through the second socket is the primary path. SIGINT to the process group stays as the fallback, and both are already recorded as fixtures.
- **Classify prompts by content.** A main prompt is `<PROMPT>` holding a bare `(%iN)` label (with or without the trailing space). Any `<PROMPT>` that contains `<math>` is a question.
- **The Phase 1 scanner gets about 75 KB of startup output.** It includes SBCL compiler notes inside `<suppressOutput>`, a 60 KB `<wxxml-symbols>` block and two `<variables>` blocks, and the symbols/variables come again when `integrate` autoloads a package. The scanner must handle large tags and split reads.
- **The Command Line Tools need an extra test flag.** With only the CLT installed, SwiftPM needs the Swift Testing framework paths. `Package.swift` now sets them for linking, but SwiftPM still only runs swift-testing when it sees the flag on the command line. Plain `swift test` builds, runs zero tests and exits 0, which looks like a pass. Until Xcode is installed, use:

      swift test -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks

  Decide whether to install Xcode or put this command in CLAUDE.md. I did not change CLAUDE.md.

## Doc and repo notes for you

- CLAUDE.md points to `docs/PHASE0_PROMPT.md`, but the file is at the repo root. It was open in vim (`.PHASE0_PROMPT.md.swp`), so I left it there, untracked.
- The fixtures contain machine-specific text: your home path, `/var/folders/...` temp names, ports, PIDs and memory addresses. The README in the fixtures folder lists them so Phase 1 tests don't compare them literally.

## Not tested

- Restarting, the 5-second connect watchdog, kill while busy, and the orphan-cleanup signal handlers (all Phase 1).
- The debugger prompt `(dbm:N)`, LDB, `to_lisp()` mode, SVG plots, animations (`slide`), `wxdraw`, and the help-format and version setup commands, which the spike skips.
- Paths with spaces or non-ASCII characters, and a second Maxima release (needed for the protocol-drift risk).
- Whether gnuplot needs `DISPLAY`: both plots went to PNG with no window and no `DISPLAY` set, but no on-screen terminal was tried.
