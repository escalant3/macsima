# Maxima transcripts

Phase 0 recorded 01 to 25; Phase 1 added the scenarios numbered 26 and up, glue mode only,
by running `maxima-spike record` for just those scenarios so the older files stay unchanged.

## Phase 0

Recorded 2026-10-18 on macOS 26.5.1 (arm64) with Homebrew Maxima 5.50.0 (revision 2) on SBCL 2.6.9
(threads: yes), using `maxima-spike record` (`Sources/maxima-spike`). Re-record with
`Tests/Fixtures/transcripts/record.sh` after `swift build`.

- `scenarios/NN-name.scn`: what was sent, one statement per line (directives start with `!`, see the spike's
  header comment). `NAME.raw.scn` / `NAME.glue.scn` run in one mode only.
- `raw/`: plain Maxima over the `-s` socket, no glue Lisp.
- `glue/`: the same after sending `Sources/MaximaKit/Resources/wxMathML.lisp` (wxMaxima 13e4aee) as one `:lisp-quiet` line,
  followed by wxMaxima's setup commands (gnuplot path, interrupt channel, prompt prefix and suffix).

Each scenario runs in a fresh Maxima. Per scenario:

| File | Contents |
| --- | --- |
| `NN-name.txt` | Every byte received on the control socket, verbatim (no CR stripping) |
| `NN-name.sent.txt` | Everything sent, in order; the glue Lisp is shown as a one-line placeholder, signals and interrupt-channel writes as `<!...>` |
| `NN-name.stdio.txt` | Maxima's own stdout/stderr (not the socket): only `Connecting Maxima to server on port N` |

Things to know when using these as test fixtures:

- The auth token is the fixed `PHASE0-TEST-TOKEN`, so `<wxxml-key>PHASE0-TEST-TOKEN</wxxml-key>` appears in every glue file.
- Variable content: the `pid=N` first line, ports, temp-file names under `/var/folders/...`, the
  `Interactive interrupt at #x...` address, and paths under `/Users/diego` (user init file
  `~/.maxima/maxima-init.mac` is loaded and announced in the banner). Tests must not compare these literally.
- Every glue file starts with about 75 KB of setup output: SBCL compiler notes inside `<suppressOutput>`,
  `<wxxml-symbols>` and two `<variables>` blocks. The interrupt scenarios repeat the symbols and variables
  blocks when `integrate` autoloads a package.
- Questions (`asksign`) have no marker in raw mode (the spike moved on after 1.5 s of silence); in glue mode
  they arrive as `<PROMPT><math>...</math></PROMPT>`.
- `23-plot` raw wrote `/tmp/macsima-phase0-plot.png`; glue `wxplot2d` wrote a `maxout_*.png` in Maxima's
  temp folder. Neither image is kept here.

| # | Scenario | Sent |
| --- | --- | --- |
| 01 | plain result | `integrate(sin(x), x);` |
| 02 | `$` terminator | `a:3$`, `a;` |
| 03 | polynomial | `expand((x+1)^5);` |
| 04 | math error | `1/0;`, `2+2;` |
| 05 | syntax error | `x+;`, `2+2;` |
| 06 | user error | `error("custom failure");`, `2+2;` |
| 07 | asksign via integrate | `integrate(1/(x^2+a),x);`, `positive;`, `2+2;` |
| 08 | asksign direct | `asksign(y);`, `pos;`, `2+2;` |
| 09 | solve | `solve(x^2-2=0,x);` |
| 10 | matrix | `matrix([1,2],[3,4]);` |
| 11 | derivative | `diff(sin(x)^2,x);` |
| 12 | infinite sum | `sum(1/k^2,k,1,inf), simpsum;` |
| 13 | limit | `limit(sin(x)/x,x,0);` |
| 14 | float (ARM64 smoke test) | `float(%pi);`, `float(x);`, `float(1/3);` |
| 15 | print, `$` | `print("hello")$` |
| 16 | string | `"a string";` |
| 17 | Taylor series | `taylor(exp(x),x,0,5);` |
| 18 | Greek, root | `%alpha^2+sqrt(2)/2;` |
| 19 | 1D display | `display2d:false$`, `(x+1)^2/y;` |
| 20 | Lisp escape | `:lisp (+ 1 2)`, `2+2;` |
| 21 | interrupt by SIGINT | long `integrate`, wait 3 s, SIGINT to the process group, `2+2;` |
| 22 | interrupt channel (glue only) | long `integrate`, wait 3 s, `interrupt` on the second socket, `2+2;` |
| 23 | plot | raw `plot2d(...,[png_file,...])`; glue `wxplot2d(sin(x),[x,0,%pi]);` |
| 24 | tex | `tex(x^2/2);` |
| 25 | quit | `quit();` (socket closes, no output) |
| 26 | prelude lines (glue only, Phase 1) | `:lisp-quiet (setq $linel 80)` and `*wx-cell-id*` lines with `!send`, then `2+2;`, `3+3;`: no prompt for the prelude |
| 27 | background job (glue only, Phase 1) | cell id `cell-A`, `wx-spawn-async` that prints `done` after 1 s, cell id `cell-B`, `2+2;`, `3+3;`: the `<wxasync>` keeps `cell-A` |
| 28 | more errors (glue only, Phase 1) | `?car(1);` (Lisp error), `error("value is", x^2);` (message as a `math` chunk), `2+2;` |
| 29 | Lisp mode (glue only, Phase 1) | `to_lisp();`, `(+ 1 2)`, `(to-maxima)`, `2+2;` |
| 30 | debugger (glue only, Phase 1) | `debugmode(true)$`, `error("x");`, `:top`, `2+2;` |
