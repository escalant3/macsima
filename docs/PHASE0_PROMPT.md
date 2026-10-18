Read CLAUDE.md and docs/BOOTSTRAP.md. We are doing Phase 0 only.

Goal: prove the Maxima integration works on this Mac with my Homebrew Maxima 5.50.0, and record what the real output looks like.

1. Run the checks in CLAUDE.md: `maxima --version` and the SBCL thread check. Report both results. If threads are "no", that is fine: interrupts will fall back to SIGINT, so just note it.
2. Create the Swift package skeleton from the repository layout in BOOTSTRAP.md (empty targets are fine) with the LICENSE (GPL-2.0-or-later) and a stub docs/WXMX_COMPAT.md.
3. Turn the Phase 0 spike sketch in BOOTSTRAP.md into a small command-line target that listens on a loopback port, spawns /opt/homebrew/bin/maxima with `-s <port>`, accepts the connection, sends `integrate(sin(x), x);` and prints the raw bytes. The sketch is untested, so expect to fix it.
4. Record raw transcripts under Tests/Fixtures/transcripts/ for about 20 commands: a plain result, a `$`-terminated command, an error, an `asksign` question, a long `integrate` followed by an interrupt (SIGINT is fine), and a `plot2d` or `wxplot2d`.
5. Then send the glue Lisp from wxMathML.lisp (fetch the current file from the wxMaxima repository on GitHub, keep its notices) with `:lisp-quiet` and record the tagged XML for the same commands.
6. Write a short docs/PHASE0_REPORT.md: what worked, what differed from BOOTSTRAP.md, the thread-check result, and anything that changes the plan.

Do not start Phase 1. Do not add packaging, notarization or bundling. Stop when the report is written and show me the summary.
