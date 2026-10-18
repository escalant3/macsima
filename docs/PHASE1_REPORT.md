# Phase 1 report: engine kit (MaximaKit)

2026-10-18 · macOS 26.5.1 (arm64) · Swift 6.3.3 · Homebrew Maxima 5.50.0 on SBCL 2.6.9 · gnuplot from Homebrew

**Result: the exit criterion is met.** `maxima-session` runs a 50-command script against real Maxima: 52 statements, 2 answers, 49 cells, two Maxima processes. The script includes four kinds of error, two questions, an interrupt through the channel, an interrupt through SIGINT, and a kill while busy followed by a restart. The run takes 6.3 s and passes every `!expect` check. Afterwards no Maxima, SBCL or gnuplot process remains, and neither do `maxout*` files or session temp folders. The same script runs as an integration test.

## Summary

- **Engine.** `MaximaKit` holds the tag scanner, prompt classifier, statement splitter, process and loopback transport, the `MaximaSession` actor, and the orphan guard. It has no UI and builds with no warnings in Swift 6 mode under strict concurrency.
- **Tests.** 49 Swift Testing tests pass in about 11 s (`swift test` reports "Test run with 49 tests in 9 suites passed").
  - Most of them run without Maxima: they replay the transcripts, and every glue scenario goes through the session with two random chunkings.
  - 8 integration tests (one with two cases) use the real Maxima and are skipped when `/opt/homebrew/bin/maxima` is missing.
- **New fixtures.** Five glue transcripts (26 to 30): prelude lines, a `wxasync` background job, Lisp errors, `to_lisp()` and the debugger.
- **Two surprises, both fixed and recorded in BOOTSTRAP.md:**
  1. A spawned child inherits the host's signal mask. Under the test runner, Maxima started with SIGTERM blocked.
  2. gnuplot scripts have random names, not `maxout*`. Cleaning up by name pattern would leave files behind, so each Maxima gets a private temp folder instead.

## What works

| Area | What it does | Tested by |
| --- | --- | --- |
| Tag scanner | Splits the socket bytes into prompt, math, text-line and tag events. Matches only attribute-less top-level tags, is safe with UTF-8 split across reads, and drops CRs | Each of the 54 fixtures gives identical events fed whole, 1 byte at a time, and in random chunks (4 seeds, two size ranges). The 75 KB startup takes 13 ms whole and 156 ms byte by byte |
| Prompt classifier | `(%iN)` with or without a space → main; `(dbm:N)` → debugger; `MAXIMA>` → Lisp; anything else → question. Trims surrounding whitespace | Strings, plus every prompt in every glue fixture |
| Statement splitter | Splits on `;` and `$` outside strings and nested `/* */`; keeps `:lisp` lines whole; adds a missing `;`; skips comment-only pieces; refuses unbalanced or mismatched `()[]{}`, or an unclosed string or comment, with line and column | Unit tests |
| Process and transport | Listens on 127.0.0.1:0, spawns `maxima -s <port>` with posix_spawn in a new process group, a 64-byte random token, a private temp folder, and a clean signal mask. Accepts the control connection, and an interrupt channel only after its token line | Fake executables (missing, exits early, never connects) and real Maxima |
| Watchdog | `.slowStart` after 5 s. An exit before connecting is retried up to 3 attempts in all, then `failedToStart` with the tail of Maxima's own log. Gives up after 30 s with no connection | Fake executables |
| Session | `starting → authenticating → configuring → idle ⇄ busy`, plus `question`, `debugger`, `lisp` and `dead`. Drops all output until the echoed token matches. Sends the `linel` line before each statement and the `*wx-cell-id*` line when the cell changes. Sends the next statement only after a main prompt | Replay of all 30 glue scenarios; real-Maxima smoke test |
| Errors | Recognized from plain text (strings listed below). By default the rest of the cell is skipped and later cells still run; `abortCellOnError = false` keeps going | Replays of 04, 05, 06, 28, 30; exit script |
| Questions and debugger | `.question` and `.debugger` events. `answer(_:)` replies, adding `;` to an answer that has none | Replays of 07, 08, 30; real `asksign` answered `pos` without `;` |
| Lisp mode | After `to_lisp()`, cells are sent verbatim with no prelude, until `(to-maxima)` | Replay of 29; exit script |
| `wxasync` | Routed by `<id>` to that cell's stream if it is still open, otherwise to `session.events` | Replay of 27, both cases |
| Interrupt | The channel is used when it is up, otherwise SIGINT to the group. Either can be forced. An interrupt skips the rest of the cell and drops queued cells | Replays of 21, 22; real Maxima, both paths |
| Kill and restart | Closes the sockets, sends SIGTERM to the group, sends SIGKILL after 2 s, and deletes the temp folder. Open cells end with `.sessionDied`. A restart while busy took 0.32 s | Real Maxima: kill while busy, restart while busy, plot files gone after shutdown |
| Orphan guard | A fixed C array of process groups. SIGTERM, SIGINT and SIGHUP handlers send SIGKILL to them, then re-raise | SIGTERM to `maxima-session` while Maxima is busy computing: the group is gone afterwards |

## Public API

```swift
let session = MaximaSession(configuration: MaximaConfiguration())   // paths, lineWidth, abortCellOnError, timeouts
try await session.start()                      // returns when idle; throws MaximaError
let cell = try await session.evaluate(cellID: "uuid", text: "1/0; 2+2;")   // throws .split(SplitError), .notRunning
for await event in cell { ... }                // CellEvent, always ends with .finished(CellOutcome)
try await session.answer("pos")                // in .question or .debugger
await session.interrupt(via: .automatic)       // .channel, .signal; returns InterruptResult
try await session.restart()
await session.kill()                           // state .dead; start() works again
await session.shutdown()                       // kill and end session.events
for await e in session.events { ... }          // SessionEvent: state, slowStart, interruptChannelReady,
                                               // tag (variables, wxxml-symbols, ...), async, output, died
await session.state                            // SessionState
```

- `CellEvent` cases are `started(index, Statement)`, `math(xml)`, `text(line)`, `question(raw)`, `debugger(level)`, `error(kind, message)`, `interrupted`, `skipped(Statement)`, `prompt(label)`, `async(xml)`, `tag(name, content)` and `finished(outcome)`.
- `CellOutcome` is `completed`, `failed(ErrorKind)`, `interrupted` or `sessionDied(reason)`.
- Lower layers are public too: `TagScanner`, `PromptClassifier`, `StatementSplitter`, `GlueLisp`, `MaximaTransport` and `ProcessTransport`, `OrphanGuard`, and `ScriptRunner` (the `.mxs` format) with `MathText` (a log-only tag stripper).

## Error text relied on

Maxima 5.50.0 on SBCL (see `OutputClassifier.swift`):

- A line containing `-- an error.`: merror and `error()`, including ` -- an error.  Entering the Maxima debugger.` The message is the plain-text lines before it. When `error()` is given an expression, the message arrives as a `math` chunk instead, and the error's text is empty.
- A line starting `incorrect syntax:`: the message is that line plus the echo and caret lines.
- `Maxima encountered a Lisp error:`: the message runs up to `Automatically continuing.` If the message is `User interrupt` or starts with `Interactive interrupt at`, the result is `.interrupted` instead of an error, whoever sent the interrupt.

## What differed from BOOTSTRAP.md (updated)

1. **The key is nested.** `<wxxml-key>` sits inside `<suppressOutput>`, so the session looks inside that tag's content.
2. **`wxasync` carries the cell ID as an `<id>` child, not an attribute.** Only the Lisp macro `wx-spawn-async` produces it.
3. **Prompt details.** Lisp and debugger prompts start with a newline inside `<PROMPT>`. `to_lisp()` prints no result. The debugger's error line has two spaces before `Entering`.
4. **Cleanup by pattern misses files.** gnuplot scripts get random names (`2s7glnregj0fo42t.gnuplot`), so each Maxima gets a private temp folder (`TMPDIR` and `maxima_tempdir`), and a kill deletes the folder. Folders left by a host that died are swept on the next start.
5. **Signal mask.** posix_spawn passes the parent's blocked and ignored signals to the child. Under the test runner, SIGTERM did nothing until SIGKILL. The spawn now resets both.
6. **The interrupt channel arrives after `start()` would return.** `start()` now waits up to 3 s for it when the glue's startup `variables` promise one.
7. **Layout.** `wxMathML.lisp` moved from `Resources/lisp/` to `Sources/MaximaKit/Resources/` (unmodified), because SwiftPM resources must live in the target. A new executable target, `maxima-session`, was added.
8. **Error text and error handling.** BOOTSTRAP.md had no error text section; one now lists the strings above.

## Deviations from the Phase 1 plan

- **Connections before authentication are rejected, not queued.** If another local process connects first and does not echo the token, `start()` fails with `authenticationFailed`. Promoting the next connection to control was planned but not built. The impostor gets only the glue, never the token.
- **wxMaxima's help-format and version setup lines are not sent.** These are `$wxmaximaversion` and the related variables. The same was true of the spike.

## Still untested

- The SBCL low-level debugger (LDB).
- Paths with spaces or non-ASCII characters (Maxima path, temp folder, `MAXIMA_INITIAL_FOLDER`, which is never set by the tests).
- A second Maxima release (the protocol-drift risk).
- SVG plots, `slide` animations, `wxdraw`.
- A Lisp without threads: the SIGINT fallback without a channel is tested only by replay.
- The `statusbar`, `worksheetexport` and `wxxml-asciimath` tags: routed, but never seen live.
- `wxasync` and `quit()` against the live process: replay only.
- The orphan guard on SIGINT and SIGHUP. Only SIGTERM to the host was tried.
  - A host killed with SIGKILL cannot be caught: a busy Maxima keeps running until it next reads its closed socket. Its temp folder is swept on the next start.
- Interrupting while a question is waiting.
- An impostor connection.

## What changes Phase 2

- **Plot files are short-lived.** They live in the session's temp folder and disappear on kill, restart and shutdown. The worksheet must load the image data (and later embed it in `.wxmx`) as soon as the `img` event arrives.
- **Coalescing.** The streams are unbounded and deliver every event. The UI should batch updates, for example every 100 ms as wxMaxima does.
- **Cell IDs.** `wxasync` routing needs stable per-cell IDs. Phase 2 cells should carry UUIDs and pass them to `evaluate(cellID:text:)`.
- **Error display.** An `error()` with an expression has an empty message; its text is in the preceding `math` chunk, so show the cell's output, not just the message.
- **Answer cells.** A question is the raw `<PROMPT>` content (math XML) and needs the same renderer as results. `answer` adds `;`.
- **Labels.** `.prompt(label:)` gives the input label of each statement, which is useful for showing `(%iN)`.

## Commits

`d194ac1` scanner · `899f070` Lisp-mode and debugger fixtures · `0eab20b` classifier and splitter · `0b2f111` glue Lisp moved to a resource · `ff1c0b6` process and transport · `22ae7b7` prelude, async and error fixtures · `c2f2215` session actor · `9c83776` orphan guard, interrupt, kill and restart tests · `04f1a53` `maxima-session` and the exit test.

Run the exit test by hand with `swift build && .build/debug/maxima-session Tests/Fixtures/scripts/phase1-exit.mxs` (add `--quiet` for a summary).
