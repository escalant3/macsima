# Phase 1 plan: MaximaKit engine kit

## Context
Phase 0 showed that the wire protocol works against Homebrew Maxima 5.50.0, and it left 25 glue and 24 raw transcripts in `Tests/Fixtures/transcripts/`. Phase 1 turns the throwaway spike (`Sources/maxima-spike/main.swift`) into a tested engine in `Sources/MaximaKit`, with no UI, no MathML and no .wxmx. It is done when a 50-command scripted session runs against the real Maxima, with errors, a question, two kinds of interrupt and a kill plus restart, and leaves no processes or `maxout*` files behind.

## What the fixtures say (this plan relies on these facts)
- The startup stream is: `pid=N` and banner lines, a bare `(%i1) ` as plain text (no tag, sent before the glue), then `<suppressOutput>` with **`<wxxml-key>` nested inside it**, followed by SBCL notes, then `<wxxml-symbols>` (60 KB) and two `<variables>` blocks. There are no CRs in the fixtures, but the scanner strips them anyway.
- Error text on the plain-text path:
  - Maxima error: a line ending ` -- an error. To debug this try: debugmode(true);`, with the message on the lines before it (04, 06).
  - Syntax error: a line starting `incorrect syntax:`, then an echo of the input and a caret line. The label does not advance (05).
  - Lisp error or interrupt: `Maxima encountered a Lisp error:`, then a blank line, then ` User interrupt` (channel, 22) or ` Interactive interrupt at #x…` (SIGINT, 21), then `Automatically continuing.` and the debugger-hook line.
- A question is `<PROMPT><math>…</math></PROMPT>`. The answer (`pos;`) brings back a `math` chunk and then a main prompt (07, 08).
- After `:lisp (+ 1 2)` the output is `3` followed by `<PROMPT>(%i1)</PROMPT>`, without the trailing space (20).
- `wxasync` (wxMathML.lisp:2971) has the form `<wxasync><id>ID</id><mth>…</mth></wxasync>`. The cell ID is a child element, not an attribute. No Maxima-level function triggers it; it needs the Lisp macro `wx-spawn-async`.
- Plot files are named `maxout_<lispPID>_…` in Maxima's temp folder.

## Layout changes
- Move `Resources/lisp/wxMathML.lisp` to `Sources/MaximaKit/Resources/wxMathML.lisp` with `git mv`, so that `Bundle.module` can load it. SwiftPM resources must live inside the target. The file stays unmodified with its notices kept. Update `record.sh`, the two READMEs and the layout in BOOTSTRAP.md.
- New executable target `maxima-session`. Script runner code lives in MaximaKit (`Scripting/`) so the CLI and the integration test share it.
- The spike stays untouched so the fixtures stay reproducible.
- Commits use explicit pathspecs. The already-staged `docs/PHASE0_PROMPT.md` and the untracked `docs/PHASE1_PROMPT.md` are yours and stay out of my commits.
- New behaviour gets its own fixture-recording commit (with the spike and `record.sh`, scenario files `*.glue.scn`), placed just before the step that uses it.

## Steps (one commit per step, after `swift build` and `swift test` show N > 0)

### 1. Tag scanner: `Sources/MaximaKit/Protocol/TagScanner.swift`
- `struct TagScanner { mutating func feed(_ Data) -> [ScannerEvent]; mutating func flush() -> [ScannerEvent] }`
- `enum ScannerEvent: Equatable, Sendable { case prompt(String), math(String) /* whole element, raw */, text(String) /* one line */, tag(name: String, content: String) }`
- It works on bytes, so UTF-8 split across reads is safe. It drops 0x0D. It matches only `<name>` with no attributes, for the known top-level names (`PROMPT`, `math`, `mth`, plus the 10 generic ones). It holds a buffer tail that could be the start of a known open tag. Content runs to the first `</name>`; inner tags cannot repeat the outer name. It keeps a scan offset, so feeding 1 byte at a time stays O(n). Unknown `<…>` is text.
- Text is one event per complete line. A partial line is held until a newline, a tag or `flush()`. That makes the events the same however the input is chunked. `pid=N` comes out as an ordinary text line.
- `suppressOutput` is a generic tag event. The session looks for the key inside it as well as in a top-level `wxxml-key`.
- Tests (`TagScannerTests`): every raw and glue fixture fed whole and in seeded random chunk sizes (several seeds, including 1 byte at a time) gives identical events. Plus a split multibyte character (the Greek fixture), a partial tag at the end of a chunk, an unknown tag treated as text, and a timed run over the 75 KB startup output: print the duration and assert a generous bound.
- Test support: `Fixtures.swift` (loader) and `Normalize.swift`, which replaces `pid=N`, ports, `/var/folders/...` names, `#x…` addresses and `/Users/<name>` before any literal comparison.

### 2. Prompt classifier and statement splitter
- First record fixtures: `29-to-lisp` (`to_lisp();`, `(+ 1 2)`, `(to-maxima)`, `2+2;`) and `30-debugger` (`debugmode(true)$`, `error("x");`, `:top`, `2+2;`). That gives fixture-backed `MAXIMA>` and `(dbm:N)` prompts. If either cannot be captured, I say so and test from strings only.
- `PromptClassifier.classify(_ content:) -> PromptKind` returns `.main(label: Int)` for `^\(%i\d+\) ?$`, `.debugger(level:)` for `^\(dbm:\d+\) ?$`, `.lisp` for trimmed `MAXIMA>`, and otherwise `.question(content)` (anything containing `<math>`, or other text). The rule "any prompt counts as main while in Lisp mode" lives in the session. Tested against the prompts of every glue fixture.
- `StatementSplitter.split(_ cell:) throws(SplitError) -> [Statement]`, where `Statement` holds the text and a terminator of `;`, `$` or none (for `:lisp`). It handles strings with `\"`, nested `/* */`, backslash escapes outside strings, and `:lisp`/`:lisp-quiet` lines (to end of line). It adds a missing `;` and skips empty or comment-only pieces. It checks `()[]{}` balance and nesting across the cell and reports an error with the position and character. Unit tests cover the tricky cases (`;` in strings and comments, a `$` inside a string, a trailing comment, `:lisp` mixed with statements, a mismatched `(]`, an unclosed string or comment).

### 3. Process and server: `Sources/MaximaKit/Engine/`
- `LoopbackServer` uses NWListener on 127.0.0.1 port 0, as the spike did. The first connection is the control candidate. A second connection becomes the interrupt channel only when its first line equals the token; otherwise it is closed. If the control candidate never authenticates, it is closed and the next connection gets a chance.
- `MaximaProcess` uses posix_spawn with SETPGROUP, stdin from /dev/null, and stdout/stderr to a log in the session temp folder (its tail goes into error messages). A DispatchSource process-exit monitor calls waitpid and so reaps the child.
- Environment:
  - `MAXIMA_AUTH_CODE` is 64 random bytes from `SecRandomCopyBytes`, base64-encoded.
  - **Per-session temp folder** (`mkdtemp`, `macsima-<pid>-XXXX`), set both as `TMPDIR` and, during setup, as `maxima_tempdir`. Kill can then clean up `maxout*` files without touching other Maxima instances (wxMaxima's generic delete would). On startup, folders left behind by dead host PIDs are swept away.
- `GlueLisp.command(from:)` is ported from the spike's `glueCommand`. The setup lines after authentication are the same as the spike's plus `maxima_tempdir`. No prompt is awaited after them.
- Watchdog: no connection within 5 s emits a `.slowStart` event. An exit before connecting retries up to 2 more times, then throws `MaximaError.failedToStart(attempts:, logTail:)`. There is a hard connect timeout of 30 s.
- The transport protocol sits behind `MaximaTransport` (the real `ProcessTransport`, or a fake) and emits `.data`, `.closed`, `.interruptChannelReady`, `.processExited`, `.slowStart`.
- Test: an integration test (skipped when `/opt/homebrew/bin/maxima` is missing) checks that the connection is made, the key is seen, the interrupt channel authenticates, shutdown works and nothing is left behind.

### 4. MaximaSession actor and state machine: `Sources/MaximaKit/Session/`
- Record fixtures first:
  - `26-prelude`: `!send :lisp-quiet (setq $linel 80)`, a `*wx-cell-id*` line, then `2+2;`. Confirms the prelude lines get no prompt.
  - `27-async`: set the cell ID, then `:lisp-quiet (wx-spawn-async (sleep 1) (wx-async-text "done"))`, `!sleep 2`, `2+2;`.
  - `28-errors-more`: `?car(1);` for a Lisp error, and `error("value is", x^2);` to see whether math shows up inside an error.
- States are starting, authenticating, configuring, idle, busy, question, debugger, lisp and dead. Authenticating: the glue has been sent, and everything is dropped until a key matches. Configuring: the setup lines are sent, then the session goes straight to idle.
- API:
  ```swift
  public actor MaximaSession {
    public init(configuration: MaximaConfiguration = .init())
    public var state: SessionState { get }
    public nonisolated var events: AsyncStream<SessionEvent>   // state changes, async output for finished cells, variables/symbols/statusbar tags, death
    public func start() async throws
    public func evaluate(cellID: String, text: String) throws -> AsyncStream<CellEvent>
    public func answer(_ text: String) async throws
    public func interrupt() async
    public func restart() async throws
    public func shutdown() async
  }
  ```
  `CellEvent` is `.started(index, Statement)`, `.math(String)`, `.text(String)`, `.question(String)`, `.error(ErrorKind, message)`, `.interrupted`, `.skipped(Statement)`, `.prompt(label)`, `.async(String)`, `.tag(name, content)` and `.finished(CellOutcome)`.
- Queue:
  - Cells run FIFO. Before each statement the session sends `:lisp-quiet (setq $linel N)`, plus the `*wx-cell-id*` line when the cell changes; neither is sent in Lisp mode. The next statement goes out only after a main prompt.
  - An error stops the rest of the cell (the skipped statements are reported) and later cells continue. This can be turned off with `abortCellOnError`.
  - An interrupt stops the current cell and clears the queued cells.
- Error detection uses the three markers above, collected while the statement runs and decided at the next main prompt. A Lisp error is reported as `.interrupted` when the message is `User interrupt` or `Interactive interrupt at` and an interrupt was requested, and as `.lispError` otherwise. `docs/PHASE1_REPORT.md` documents exactly which strings are relied on.
- `wxasync`: the session parses `<id>` and routes the event to that cell's stream if it is still open, or to `events` otherwise.
- The `*wx-interrupt-channel-available*` value from `variables` decides whether to wait for the channel.
- Tests:
  - A `ReplayTransport` cuts a fixture into segments at each `</PROMPT>`. Segment 0 is released on the glue send; each later segment is released on a trigger, meaning a statement send (not `:lisp-quiet`), an answer, `interrupt()` or SIGINT.
  - Every glue scenario is run through the session with the fixture token `PHASE0-TEST-TOKEN`. The tests check the state sequence, the events, the abort on error, a question answered, interrupt handling, `quit()` leading to dead, async routing, a key mismatch dropping data, and a closed socket finishing every open stream with `.sessionDied`.

### 5. Interrupt, kill, restart, orphan guard
- Interrupt sends `interrupt\n` on the authenticated channel, and otherwise falls back to `killpg(pgid, SIGINT)`.
- Kill:
  1. Cancel both connections.
  2. `killpg(SIGTERM)`.
  3. Wait up to 2 s for the exit monitor.
  4. `killpg(SIGKILL)` and waitpid.
  5. Delete `maxout*` files and the session temp folder (and also `maxout_<pid>_*` in the system TMPDIR, as a safety net).
- `restart()` is kill followed by `start()`; any streams still open end with `.sessionDied`.
- `OrphanGuard` holds a fixed-size static `pid_t` array with an atomic count (`nonisolated(unsafe)`, documented). Handlers are installed with `sigaction` for SIGTERM, SIGINT and SIGHUP. A handler calls `kill(-pgid, SIGKILL)` for each entry, then restores the default handler and re-raises. The app and the CLI install it with `OrphanGuard.install()`; tests do not install it in the test runner.
- Tests:
  - Unit tests: the replay transport records which interrupt path it used, and the guard's register and unregister work.
  - Integration test (skipped without Maxima): kill while busy, restart, evaluate `2+2;`, then check that the old pgid is empty (`kill(-pgid, 0)` returns ESRCH) and the temp folder is gone.
  - Integration test (skipped if the `maxima-session` binary is missing): start a long script, send SIGTERM to the CLI, check that the pgid is gone.

### 6. Exit test: `Sources/maxima-session/main.swift` and `Tests/Fixtures/scripts/phase1-exit.mxs`
- The script format extends `.scn`:
  - One statement per line is one cell.
  - `!cell … !end` groups lines into one cell.
  - `!async <stmt>` starts a statement without waiting for it.
  - The other directives are `!sleep`, `!answer <text>`, `!interrupt` (channel), `!sigint`, `!kill`, `!restart` and `!expect error|skipped|interrupted|question`, so that a run can fail.
- The script has at least 50 executed commands. It includes plain results, `$` statements, a math error, a syntax error and `error()` (one inside a multi-statement cell, to show the skip), `asksign` answered with `!answer pos;`, an interrupt through the channel, an interrupt through SIGINT, a kill while busy followed by a restart, `wxplot2d` (checking that the PNG exists), and `:lisp (+ 1 2)`.
- The CLI prints a readable log (`[c12] > 1/0;`, `[c12] error(maxima): …`, `[c12] skipped: 2+2;`) and exits non-zero if an `!expect` fails.
- `Phase1ExitTests` runs the same script in-process through `ScriptRunner` (skipped without Maxima, `.serialized`). It then checks the PIDs and pgids the session reports, rather than doing a global pgrep that would trip over another wxMaxima. For information only, it also logs a global `pgrep -l maxima|gnuplot|sbcl`. It confirms no `maxout*` files remain in either temp location and that the plot PNG was removed at shutdown.

### 7. Report
- Write `docs/PHASE1_REPORT.md` covering:
  - what works and the public API;
  - the error strings relied on;
  - how BOOTSTRAP.md differed (and update BOOTSTRAP.md: key nested in `suppressOutput`, `wxasync` ID as a child element, the per-session temp folder, the resource move, and anything else found);
  - what is still untested (LDB, paths with spaces or non-ASCII characters, a second Maxima release, SVG, `slide`, help-format and version setup lines, host killed with SIGKILL, which the guard cannot catch);
  - what changes Phase 2 (100 ms coalescing still to do on the UI side, temp-folder lifetime versus plot loading).
- Update "Current phase" in CLAUDE.md. Stop there and show you the summary.

## Verification
- Every step: `swift build` with no warnings under strict concurrency, then `swift test`, reading the Swift Testing line "Test run with N tests … passed" and checking that N grows.
- Steps 3, 5 and 6 run against the real `/opt/homebrew/bin/maxima`. Step 6 also runs `.build/debug/maxima-session Tests/Fixtures/scripts/phase1-exit.mxs` by hand, followed by `pgrep -l -f maxima`, `pgrep -l gnuplot` and `ls $TMPDIR | grep maxout`.
- I will report anything I could not run.
