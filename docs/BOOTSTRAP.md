# Native macOS Maxima front end: bootstrap and feasibility

Oct 14, 2026 · @Someone

A native macOS front end for Maxima is feasible: wxMaxima's whole link to the engine is one loopback socket plus one Lisp file, so Maxima can stay unmodified and run as a separate process. The hard work is the worksheet editor and 2D math rendering, not the Maxima integration.

## Decisions (2026-10-18)

These answers from the project owner override the first draft wherever they differ.

- **Purpose.** A personal tool first. Sharing is optional and only if it proves worth it; there is no commercial goal. DMG packaging, bundling and notarization are deferred (see Shipping later).
- **Engine.** SBCL only, with Maxima 5.50.0 from Homebrew as the baseline. Homebrew's formula (5.50.0, revision 2) depends on sbcl and gnuplot. The app finds `maxima` and `gnuplot` under `/opt/homebrew/bin` (configurable) and does not bundle either.
- **Platform.** arm64 only, macOS 26 (Tahoe) as the minimum, current Swift and SwiftUI APIs. Ease of coding wins over compatibility with older systems.
- **License.** GPL-2.0-or-later, so wxMathML.lisp and wxMaxima's logic can be reused directly (see Licensing).
- **File format.** The long-term goal is full `.wxmx` compatibility with wxMaxima. At first the app only needs to open files it wrote itself. Every gap is tracked in `docs/WXMX_COMPAT.md` so you know what to avoid and what to warn others about (see Compatibility ledger).

**Target.** At least 1:1 feature parity with wxMaxima, with a better UI. Parity is the destination, not the first milestone: the "MVP?" column in What the GUI owns sets the order, and every missing feature is listed in the ledger until it ships.

## Findings in brief

wxMaxima is a thin shell around an unmodified Maxima: it opens a listening socket on localhost, starts the `maxima` command with `-s <port>`, and Maxima connects back to it as the client. Maxima's own man page says `-s` connects Maxima to a server and does not create one.

- **One Lisp file does the integration.** `wxMathML.lisp` is compiled into the wxMaxima binary, sent to Maxima over the socket after it connects, and switches Maxima's output to tagged XML (math, prompts, status, variables).
- **Everything you see is the GUI's job.** Cells, the evaluation queue, 2D math layout, plot display, autocomplete and file formats all live in wxMaxima's C++. Maxima only evaluates text and prints tagged text.
- **Feasible, with one real cost for a personal tool:** the worksheet editor and math layout engine. The costs of bundling, signing and notarizing Maxima only come back if you decide to share the app.
- **Effort (my estimate, not sourced):** a working spike in about two weeks, a usable MVP in roughly three to four months for one experienced Mac developer. Parity with wxMaxima is a multi-year target (its repository has 15,921 commits), so reach it in stages: the MVP column first, then the rest, with gaps tracked in the compatibility ledger.
- **No official Mac bundle to lean on.** Maxima's install page recommends MacPorts or Homebrew for macOS and keeps only older Mac builds on SourceForge, so you own the bundling.
- **UIKit is the iOS framework.** A Mac app uses AppKit with SwiftUI on top; Mac Catalyst adds nothing here.

## How wxMaxima talks to Maxima

&#91;embedded content: process and socket layout · 4 channels\]

The control socket (2) is the only channel that carries commands and results; the interrupt socket (3) and plot files (4) are side channels. Because Maxima is the client, the app must be listening before it spawns Maxima. The next section lists every step and tag.

## Wire protocol reference

Everything below comes from wxMaxima's own sources (`MaximaProcessManager.cpp`, `MaximaEvaluator.cpp`, `Maxima.cpp`, `MaximaProtocol.h`, `wxMathML.lisp`), read at the current main branch.

### Launch recipe

1. **Listen first.** Bind a TCP server on localhost. wxMaxima starts at a configured default port and increments until a bind succeeds; a native app can bind port 0 and read the port the OS picked.
2. **Set the environment.** `MAXIMA_INITIAL_FOLDER` is the worksheet's folder (Maxima reads it once at startup, so a different folder needs a restart). `MAXIMA_AUTH_CODE` is a random token (512 random bytes, base64). `LANG` is set when configured. On macOS wxMaxima also sets `DISPLAY=:0.0`, with a TODO asking whether gnuplot still needs it.
3. **Spawn.** Run `<maxima command> -s <port>` asynchronously, console hidden, as a process-group leader so the wrapper script and the Lisp child can be killed together.
4. **Accept.** Maxima connects to the server; wxMaxima accepts and sends setup commands. The socket begins with pid=N before the banner. A later second connection is treated as the interrupt channel.
5. **Watch for failure.** If the child is alive but has not connected within 5 seconds, warn the user. If it exits, retry a limited number of times, then ask the user to restart manually.

### Setup commands after connect

All are plain lines on the same socket, and none of them gets a prompt back, so do not wait for one during setup. wxMaxima strips comments and indentation and joins the Lisp file into one line of about 88 KB. The first one sends the whole glue Lisp as a `:lisp-quiet` command.

- the glue Lisp (`wxMathML.lisp`), which sets the prompt prefix and suffix to `<PROMPT>` and `</PROMPT>`, installs the XML display function and defines helper functions;
- on macOS, `:lisp-quiet (setf $gnuplot_command "<path>")`;
- the help-format command;
- `:lisp-quiet (when (fboundp 'wx-open-interrupt-channel) (wx-open-interrupt-channel "127.0.0.1" <port> "<token>"))`;
- the front-end version into Maxima variables (`$wxmaximaversion` and friends), and the prompt prefix and suffix again so the first prompt is wrapped too.

The glue Lisp's first line prints `<wxxml-key>TOKEN</wxxml-key>` with the value of `MAXIMA_AUTH_CODE`. wxMaxima starts each session as unauthenticated and discards all data from a Maxima it does not trust. I did not read the comparison code itself. Phase 1 found that in 5.50.0 the key arrives nested inside suppressOutput, so look inside that tag's content.

### Sending a command

- Trim trailing whitespace, append a newline, send as UTF-8.
- Check for unbalanced parentheses client-side first, and refuse to send if they are unbalanced.
- Before evaluating, wxMaxima sends `:lisp-quiet (setq $linel N)` (worksheet width in columns) and, when the cell changed, `:lisp-quiet (setq *wx-cell-id* "<uuid>")`. The `:lisp-quiet` prefix is skipped in Lisp mode.
- Send one statement at a time. The next goes out only when a main prompt arrives.
- Background queries run only when the queue is empty and Maxima is idle: `(wx-query-variable "x")`, `(wx-print-gui-variables)`, `(wxPrint_autocompletesymbols)`.

### Tags Maxima sends

The stream is plain text with known tags mixed in. The scanner looks for a bare `<tag>` at the start of its buffer, takes everything through `</tag>`, and treats text in between as miscellaneous output (errors, `print()` output, the startup banner). Top-level tags carry no attributes, so the scanner stays trivial; the tags inside math do carry attributes (see Math XML). Phase 0 on Maxima 5.50.0 showed that errors, print() output, tex() output and everything under display2d:false arrive as plain text between tags, so the miscellaneous-output path is a main path, not an edge case.

| Tag | Carries | The app's job |
| --- | --- | --- |
| `PROMPT` | Input label such as ` (%i3)  `, a question, a debugger prompt `(dbm:1)` or a Lisp prompt ` MAXIMA>  ` | Classify it; advance the queue or open an answer cell |
| `math` (the glue also knows `mth`; 5.50.0 sent only `math`) | One chunk of output: an optional `lbl` label plus 2D math XML | Parse into output cells |
| `suppressOutput` | Output the user asked to hide | Handled by its own reader |
| `variables` | Values of GUI-relevant variables (`numer`, `display2d`, paths, Lisp version) | Update menus and state |
| `watch_variables_add` | Variable names for a watch panel | Add to the panel |
| `wxxml-symbols` | Symbols and function templates | Feed autocomplete |
| `statusbar` | Text from `wxstatusbar()` | Show in the status bar |
| `worksheetexport` | Request to export the worksheet (HTML or TeX) | Do the export |
| `html-manual-keywords` | Help topic names | Feed help |
| `wxxml-key` | The echoed auth token | Authenticate the session |
| `wxxml-asciimath` | Maxima's own ASCII-art display block | Show in a monospace font |
| `wxasync` | Background-job output with the originating cell's `id`, carried as an id child element (only wx-spawn-async produces it) | Route to that cell |

The worker side reads with a one-second socket timeout, strips carriage returns, and processes its buffer at least every 100 ms or when it exceeds 10,000 characters, so the UI is not flooded.

### Math XML inside `mth`

The dialect follows MathML in spirit (the Lisp file credits David Drysdale's MathML printer) but uses short custom tags. Seen in `wxMathML.lisp`: `mrow`, `mn`, `mi`, `mo`, `fn`/`fnm` (functions), `msup`, `mfrac`, `q` (square root), `tb`/`mtr`/`mtd` (matrices), `sm` (sums and products), `in` (integrals), `lm` (limits), `d` (derivatives), `at`, `p` (parentheses), `st` (strings), `t`, `g` (Greek), `s`, `h`, `a`, `cj`, `ie`, `munder`, `mmultiscripts`, `hl` (boxes), `lbl` (output label), `img` (plot file) and `slide` (animation). Many tags carry an `altCopy` attribute with the plain-text form for copy and paste. All text is XML-escaped. Phase 0 on 5.50.0 also saw a lisp attribute on most inner tags, plus bracketParens, list and listdelim.

### Prompt classes

`MaximaProtocol.h` defines three prompt kinds that count as the main prompt: a numbered input label such as ` (%i3)  `, a Lisp REPL prompt ` MAXIMA>  `, and anything while the app is already in Lisp mode. The debugger prompt `(dbm:N)` is always a question, never a main prompt. Every other prompt is a question Maxima is asking the user (for example from `asksign`), and the app must show an answer cell instead of advancing its queue. Phase 0 refinement: in glue mode a question arrives as a PROMPT that contains math, while a main prompt holds a bare (%iN) label with or without a trailing space; in raw mode a question has no marker at all, so only silence tells you it is waiting. A syntax error or a :lisp line does not advance the label.

### Interrupt and kill

- **Interrupt, preferred:** Maxima's Lisp opens a second connection to the same server and sends the token; after that the app writes `interrupt` plus a newline on it. This needs a Lisp with threads, and `wxMathML.lisp` reports whether the channel is available. Confirmed in Phase 0 on Homebrew's SBCL 2.6.9: threads are on, the glue reports the channel available, and an interrupt through it stopped a long integrate; SIGINT to the process group also worked.
- **Interrupt, fallback on POSIX:** send SIGINT to the child.
- **Kill:** close the socket and Maxima's stdin, send SIGTERM then SIGKILL to the process and its children, wait up to two seconds, then delete leftover `maxout*` gnuplot and PNG files in Maxima's temp folder.
- **Orphan guard:** wxMaxima keeps a signal-safe list of child process IDs and kills them from SIGTERM, SIGINT and SIGHUP handlers, because a Maxima busy computing only notices a closed socket when it next reads.

### Plots

`wxplot2d`, `wxdraw2d` and relatives write a PNG (or SVG when `$wxplot_usesvg` is set) into Maxima's temp folder, then print an `img` tag naming the file inside `mth`. A `del="yes"` attribute tells the app it may delete the file after loading it. In the Phase 0 run on 5.50.0 the wxplot2d image arrived without del, as an img tag with a lisp attribute holding the PNG path, inside a math chunk labelled %t1, so do not rely on del. The default plot size is 800 by 600. wxMaxima probes gnuplot's terminal list and, if `pngcairo` exists, sends `(setq $wxplot_pngcairo t)`.

## What the GUI owns

Maxima evaluates text and prints tagged text. Everything below is on your side of the socket.

| Area | What wxMaxima does | MVP? |
| --- | --- | --- |
| Document model | Cells of several kinds (title, section, subsection, text, code, with outputs attached to code cells), saved as `.wxmx` (a zip with `content.xml` and images) or plain `.wxm` | Yes |
| Evaluation queue | Splits a cell into statements, tracks `;` versus `$` endings, handles `:lisp` and `to_lisp()` mode, adds a missing terminator, runs one statement at a time | Yes |
| Error handling | Optionally aborts the queue on error; parses Maxima's error text to mark the failing statement and spot in the editor | Basic |
| Questions and debugger | Non-main prompts open an answer cell; the `(dbm:N)` debugger and the SBCL low-level debugger (LDB, via the child's stdin) are special cases | Later |
| 2D math | Lays out the XML as cells (fractions, sums, matrices, boxes) with selection and copy via `altCopy` | Yes |
| Plots | Loads the PNG or SVG file an `img` tag names; animations arrive as a `slide` tag listing frames | Yes |
| Autocomplete | Symbols and templates from `wxxml-symbols`, plus a regex pass over the user's own definitions | Later |
| Variables and status | Watch panel from `variables`, status bar from `statusbar`, CPU polling of the child | Later |
| Help | Topic names from `html-manual-keywords`; opens Maxima's HTML manual | Later |
| Export and tooling | HTML, LaTeX, `.mac` and `.wxm` export, undo, search, a worksheet diff viewer | Later |
| Settings | Maxima and gnuplot paths, display options, init file `wxmaxima-init` if present | Basic |

### File formats

A `.wxmx` file's `content.xml` has a `wxMaximaDocument` root (a sample shows `version="1.1" zoom="100"`) containing `cell` elements: `type="text"` holds an `editor type="text"` with `line` children, `type="code"` holds an `editor type="input"`. That is all I confirmed; wxMaxima's manual documents the format in full, so read that section before writing the parser. Treat files as hostile input: the current release added a size cap on `content.xml` as a decompression-bomb guard and fixed hangs on corrupt archives.

### Compatibility ledger

Full `.wxmx` compatibility is a long-term goal, reached in steps. Step one reads and writes only what this app produces. After that, each gap is either closed or recorded. The ledger is a Markdown table in the repo, `docs/WXMX_COMPAT.md`, with one row per wxMaxima feature: the element or cell type, whether the app reads it, whether it writes it, a status (full, partial, missing) and what to avoid in wxMaxima if you want files this app can open.

- **No silent data loss.** When the reader meets an element it does not know, it keeps the raw XML, shows a warning on open, and writes the element back unchanged on save where it can.
- **Shareable limits.** The ledger can be pasted into the README, so anyone you share the app with sees the same list of limits.
- **Seeding it.** Start from the file format section of wxMaxima's manual, which I have not read, and from a few of your own `.wxmx` worksheets saved as test fixtures.

### What stays in Maxima

Parsing, simplification, evaluation, `%i`/`%o` labels, `tex()` output, file loading (`load`, `batch`) and calling gnuplot are all Maxima's. Your app never needs to understand Maxima syntax beyond splitting statements and matching parentheses.

## Math rendering options

Start with the simplest renderer and swap it behind a protocol; the XML parser and the cell model do not depend on the choice.

| Option | How it works | Strength | Cost and risk |
| --- | --- | --- | --- |
| A. Native layout engine | Parse the XML into a tree, lay it out with Core Text, draw in AppKit | Best selection, copy and baseline alignment; no web view | Highest effort: a layout routine per tag. wxMaxima's own release notes list layout bugs, a layout fuzzer and idempotency tests, which shows how much edge-case work this is |
| B. Web view with MathML | Translate the XML to standard MathML and show it in `WKWebView` (WebKit has long supported MathML, and macOS 26 adds a SwiftUI WebView, as far as I know) | Fast to build; good output | The custom tags (`fn`, `q`, `tb`, `sm`, `in`, `lm`, `d`, `p`, `lbl`) need a translator. A web view per cell is heavy in long worksheets; selection across native and web content is awkward |
| C. Native LaTeX library | Ask Maxima for `tex()` output and render with a Swift LaTeX package (SwiftMath and iosMath are candidates; I have not evaluated either here) | Native views, small code | Coverage gaps for CAS output such as large matrices, boxed terms and sums with limits |
| D. Maxima's ASCII art | Send `set_display(ascii)` (defined in the glue Lisp) and show the `wxxml-asciimath` block in a monospace font | Trivial; works on day one | Ugly; no copy-as-formula |

**Recommendation:** D in the spike, B for the MVP, and A only for the cases B handles poorly. B reuses the engine's XML unchanged and keeps the translator in one file you can test against captured transcripts.

## Proposed native architecture

Split the engine from the UI so the whole Maxima link can be tested without a window, using captured transcripts as fixtures.

| Module | Responsibility | Notes |
| --- | --- | --- |
| `MaximaKit` (Swift package, no UI) | Process supervisor, loopback listener, tag scanner, session state machine, evaluation queue, interrupt channel | Pure Swift; unit-tested against transcripts |
| `WXMLKit` | Parse the math XML into a tree; emit MathML (or a layout tree later) | One translator file; snapshot tests |
| `WorksheetKit` | Cell model, `.wxm` and `.wxmx` read and write, undo model | A zip library is needed for `.wxmx` |
| App target | SwiftUI shell (windows, menus, toolbar, sidebars, settings) plus an AppKit worksheet view | One Maxima process per document window, as wxMaxima does |

### Decisions

- **Process spawning.** Foundation's `Process` has no public way to make the child a process-group leader, as far as I know. Use `posix_spawn` with `POSIX_SPAWN_SETPGROUP` so you can signal the launcher script and the Lisp together.
- **Socket.** `NWListener` from Network.framework restricted to the loopback interface, port 0, then read the assigned port before spawning. Accept exactly one control connection; treat a second as the interrupt channel after the token handshake.
- **Concurrency.** An `actor MaximaSession` owns the connection and state machine and publishes an `AsyncStream` of events. Run the tag scanner off the main thread and coalesce updates, mirroring wxMaxima's worker thread that flushes at most every 100 ms.
- **State machine.** `starting`, `authenticating`, `configuring`, `idle`, `busy`, `question`, `debugger`, `lisp` and `dead`, with transitions driven by the prompt classes above. Copy this from wxMaxima rather than inventing it.
- **Worksheet view.** Prototype in AppKit (`NSTextView` on TextKit 2, one per editable cell, inside a lazily loaded stack) hosted in SwiftUI via `NSViewRepresentable`. SwiftUI's own text editor has gained rich-text editing (AttributedString, macOS 26, as far as I know), which is now worth trying first since Tahoe is the minimum. Keep the AppKit route for cross-cell selection and caret movement, which I would not bet on without a prototype.
- **Security.** Reuse wxMaxima's design: a long random token in `MAXIMA_AUTH_CODE`, drop all data until the echoed token matches, and require the token again on the interrupt channel. Any local process can connect to a loopback port, so the token is the only gate.
- **Why not UIKit or iOS.** UIKit is iOS; an iOS app cannot host this design because it spawns a child process.

## Shipping later (deferred)

Deferred by decision: this is a personal tool first, so none of this blocks the early phases. If you later share it, a DMG is realistic: wxMaxima's own build can produce one (`cmake --build . -- package` creates a `.dmg` on macOS), and its macOS target needs only wxWidgets. Your harder job is the engine you embed.

1. **Default for now: use your own Homebrew Maxima.** Maxima's install page recommends MacPorts (`sudo port install maxima +sbcl`) or Homebrew (`brew install maxima`). wxMaxima searches the PATH and `/opt/local/bin` for gnuplot because GUI apps do not inherit a shell PATH; do the same for `maxima`. This removes bundling risk for a personal build.
2. **Build a relocatable Maxima.** Build from source with SBCL (instructions are in Maxima's `INSTALL`), install into `Contents/Resources/maxima/`, and launch it through the `maxima` script with `MAXIMA_PREFIX` pointing inside the bundle. Past Mac bundles show the pitfalls: the 2011 Maxima.app swapped trees into a template and used a modified launcher script, and a 2012 mailing-list report says the 5.28.0 DMG failed, which the thread attributes to a script that built the path with a doubled slash and broke when the volume name had a space. Test with spaces and non-ASCII characters in the install path.
3. **Pin the Lisp.** A MacPorts ticket reports that SBCL 2.3.6 could not compile Maxima's `float.lisp` on ARM64 macOS, and on x86-64 it miscompiled `float`. Pin SBCL and Maxima versions, and add `float(x)` to your smoke tests.
4. **gnuplot.** Bundle it or detect it. Its license permits redistribution but asks that modifications ship as patches, so ship it unmodified with its notices. wxMaxima looks for a gnuplot next to its own executable (`../gnuplot/bin`) before the PATH.
5. **Sign inside-out.** Sign every Mach-O file in the bundle (launcher binaries, the SBCL runtime, gnuplot and its libraries) with a Developer ID certificate, hardened runtime and secure timestamp, then the app, then submit to Apple's notary service and staple the ticket. Hardened runtime is required for notarization.
6. **Entitlements, the open question.** Hardened runtime blocks writable-and-executable memory used by JIT compilers unless you add `com.apple.security.cs.allow-jit` (the recommended route, using `MAP_JIT`) or `com.apple.security.cs.allow-unsigned-executable-memory`. SBCL compiles Lisp to machine code at runtime, so it may need one of them. I found no SBCL-specific guidance, and an Apple developer thread about a JIT emulator on Apple Silicon needed several entitlements plus the sandbox turned off. Entitlements go on executables only; libraries inherit the host's. **Test this in week one.**
7. **No sandbox in v1.** Ship Developer ID, outside the Mac App Store. A sandboxed build would need network server and client entitlements for the loopback socket and careful file-access scopes, and the GPL sits awkwardly with the App Store.
8. **Architectures.** Decided: arm64 only, so there is no x86-64 or universal build to maintain or test.
9. **DMG.** Create it with `hdiutil` or a tool such as `create-dmg`, sign it, notarize it and staple it in CI.

## Licensing

This is a summary of what I read, not legal advice; get a lawyer's view before any commercial plan.

| Component | License | Consequence for you |
| --- | --- | --- |
| wxMaxima source, including `wxMathML.lisp` | GPL, with `GPL-2.0+` identifiers in the source headers | Copying or porting its code makes your app a GPL-2.0-or-later derivative |
| Maxima | GPL | Bundling it in a DMG means distributing GPL binaries, so you must provide the corresponding source |
| SBCL | Public domain, plus BSD-style notices for a few parts (LOOP, PCL) | Keep the credits and notices |
| gnuplot | Its own permissive license, with GPL as an alternative for some files | Ship unmodified with its notices |

Decision (2026-10-18): take the first path, GPL-2.0-or-later, because it is the only one that lets you copy wxMathML.lisp and port wxMaxima's code and file-format handling. It also costs nothing while the app only runs your own Homebrew Maxima, since you distribute nothing. Two paths were considered:

1. **Make the app GPL-2.0-or-later.** Simplest. You may reuse `wxMathML.lisp` and port wxMaxima's logic freely, and you stay compatible with the code you studied.
2. **Clean-room the glue.** Write your own Lisp and your own tag format, keep Maxima as a separate process talking over a socket, and license your app as you like. In a 2003 mailing-list post a Maxima developer argued that separate processes with a well-defined protocol and no commingled source are separate works under the GPL (said of gnuplot, as an opinion, not a ruling). You would still ship Maxima's source offer with the DMG. The Lisp side is small, but you lose the years of fixes inside `wxMathML.lisp`.

## Risks and open questions

| Risk | Why it matters | Test it by |
| --- | --- | --- |
| SBCL under hardened runtime | Notarization or startup could fail without the right entitlements | Deferred until you decide to share (a Homebrew Maxima is unaffected): sign and notarize a bundled Maxima and run `maxima -s` from the signed app on a clean Apple Silicon Mac |
| Interrupt reliability | The preferred interrupt channel needs a Lisp with threads; the fallback is SIGINT | Checked in Phase 0: both paths work on Homebrew's SBCL 2.6.9; keep both as fixtures |
| Protocol drift | The glue Lisp tracks Maxima internals; a 2012 rename of `MLABLE` to `MLABEL` broke output in older wxMaxima until it was updated | Pin a Maxima version; run transcript tests against two releases |
| Math layout correctness | wxMaxima needs a fuzzer and idempotency tests for its layout code | Build a corpus of captured `mth` chunks and snapshot-test the renderer |
| Relocation | Past Mac bundles broke on path handling | Install under a path with spaces and non-ASCII characters |
| ARM64 build | SBCL 2.3.6 failed to build Maxima's `float.lisp` on ARM64 macOS | Pin versions; test `float(x)` |
| gnuplot windows | wxMaxima sets `DISPLAY=:0.0` on macOS with a TODO about it | Use only PNG or SVG terminals so no window is needed |
| Scope creep | wxMaxima has 15,921 commits | Hold to the MVP column in the table above |

### Questions from the first draft

- Resolved: the baseline is Maxima 5.50.0 from Homebrew (formula page checked 2026-10-18).
- Resolved: arm64 only, macOS 26 (Tahoe) minimum.
- Resolved: GPL-2.0-or-later (see Licensing).
- Resolved: full wxMaxima compatibility is the long-term goal; first the app only has to open `.wxmx` files it wrote itself, with every gap tracked in the ledger.
- Resolved: SBCL only. To check in Phase 0: whether your SBCL was built with threads, using the one-line test in CLAUDE.md. No custom Maxima is needed either way: without threads, interrupts use SIGINT, the same fallback wxMaxima has.

## Roadmap

Durations are my estimates for one experienced Mac developer, not sourced figures. Each phase ends with a check that decides whether to continue.

1. **Phase 0, feasibility spike (done 2026-10-18).** Use your Homebrew Maxima 5.50.0. Listen, spawn, connect, send `integrate(sin(x), x);`, print the raw bytes. *Exit:* the tagged XML for a result appears in your log, and you know whether the interrupt channel works on your SBCL build (otherwise interrupts fall back to SIGINT).
2. **Phase 1, engine kit (done 2026-10-18).** Tag scanner, session state machine, evaluation queue, restart, kill, interrupt, token handshake, all tested against recorded transcripts. *Exit:* a scripted session of 50 commands that includes an error, a question, an interrupt and a kill.
3. **Phase 2, minimal worksheet (6 to 8 weeks).** Cell editing, evaluate, MathML rendering, inline plots, open and save `.wxmx`. *Exit:* save a worksheet, reopen it and re-evaluate it; then try real `.wxmx` files from wxMaxima, and record every element the app cannot handle in the ledger.
4. **Phase 3, daily driver (8 to 12 weeks).** Autocomplete, variables panel, help, export, undo, search, debugger and Lisp modes, dark mode. *Exit:* one week of real work with no fallback to wxMaxima.
5. **Phase 4, sharing (optional).** Only if the app proves worth sharing: a README with install steps and the compatibility ledger first; a notarized DMG with a bundled Maxima only if people ask (see Shipping later).

### Phase 0 results (2026-10-18)

Run on macOS 26.5.1 (arm64), Swift 6.3.3 with the Command Line Tools only, Homebrew Maxima 5.50.0 (revision 2) on SBCL 2.6.9. The exit criterion is met: the spike gets `- cos(x)` from `integrate(sin(x), x);`, and with the glue loaded the same result arrives as tagged XML with the token echoed.

| Check | Result |
| --- | --- |
| SBCL threads | yes |
| Interrupt channel | stopped a long `integrate`; Maxima printed `User interrupt` |
| SIGINT to the process group | stopped the same `integrate` |
| `float(%pi)`, `float(x)`, `float(1/3)` | correct on ARM64 |
| Cleanup with `killpg` and SIGTERM | no leftover Maxima, gnuplot or `maxout*` files |

What changes for Phase 1:

- **Interrupt.** Use the second socket as the primary path, SIGINT to the group as the fallback.
- **Prompts.** Classify by content: a PROMPT holding a bare `(%iN)` label is a main prompt, any PROMPT containing math is a question.
- **Scanner.** Startup output is about 75 KB: SBCL compiler notes inside `suppressOutput`, a 60 KB `wxxml-symbols` block and two `variables` blocks, repeated when `integrate` autoloads a package. Handle large tags and split reads.
- **Process.** Homebrew's `maxima` script `exec`s SBCL, so the spawned PID is the Lisp itself. Your `~/.maxima/maxima-init.mac` is loaded and announced in the banner, so tests must not depend on a clean banner.
- **Fixtures.** They contain machine-specific text (home path, temp names, ports, PIDs, memory addresses); the fixtures README lists them so tests do not compare them literally.

Not tested yet: restart, the 5-second connect watchdog, kill while busy, orphan cleanup, the `(dbm:N)` debugger, LDB, `to_lisp()` mode, SVG plots, animations (`slide`), `wxdraw`, the help-format and version setup commands, paths with spaces or non-ASCII characters, a second Maxima release, and whether gnuplot needs `DISPLAY` (both plots went to PNG with none set).

Tooling note (fixed by installing Xcode): with only the Command Line Tools installed, plain `swift test` builds, runs zero tests and exits 0, which looks like a pass. Tests need `swift test -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks` until Xcode is installed.

### Phase 1 results (2026-10-18)

The engine kit (`MaximaKit`) is done, and the exit test passes. A 50-command script ran against the real Maxima in 6.3 s: four kinds of error, two questions, both interrupt paths, and a kill while busy followed by a restart. Afterwards no Maxima, SBCL or gnuplot process and no temp files remained. 49 Swift Testing tests pass; most replay the transcripts, and 8 use the real Maxima.

Corrections to the sections above, found in Phase 1:

- **Temp files.** gnuplot scripts get random names, so cleaning up `maxout*` by pattern leaves files behind. Each Maxima gets a private temp folder (`TMPDIR` and `maxima_tempdir`) that a kill deletes; folders left by a crashed host are swept on the next start.
- **Signal mask.** posix\_spawn passes the parent's blocked and ignored signals to the child, so Maxima can start with SIGTERM blocked. Reset both when spawning.
- **Interrupt channel timing.** The second connection arrives after the first idle prompt; `start()` waits up to 3 s for it when the glue says one is coming.
- **Prompts.** Lisp and debugger prompts start with a newline inside PROMPT, and `to_lisp()` prints no result.
- **Errors.** Maxima 5.50.0 on SBCL signals errors as plain text: a line containing `-- an error.`, a line starting `incorrect syntax:`, or `Maxima encountered a Lisp error:` up to `Automatically continuing.` A Lisp error saying `User interrupt` or `Interactive interrupt at` is an interrupt, not an error. When `error()` gets an expression, the message is in the preceding math chunk.
- **Authentication.** A connection that arrives before Maxima's and does not echo the token makes `start()` fail; it receives the glue but never the token.

What Phase 2 inherits: plot files vanish on kill, restart and shutdown, so the worksheet must read image data as soon as the img event arrives. The event streams are unbounded, so the UI must batch updates (about every 100 ms). Cells need stable UUIDs for `wxasync` routing, and a question's prompt is math XML that needs the same renderer as results.

Still untested: LDB, paths with spaces or non-ASCII characters, a second Maxima release, SVG plots, `slide`, `wxdraw`, a Lisp without threads, the orphan guard on SIGINT and SIGHUP, interrupting while a question is waiting, and an impostor connection.

## Bootstrap kit

### Repository layout

```text
Macsima/
  Package.swift
  LICENSE                GPL-2.0-or-later
  README.md
  CLAUDE.md              project rules and pointers for Claude Code
  Sources/
    MaximaKit/           engine: process, socket, scanner, session
    WXMLKit/             math XML to MathML (later a layout tree)
    WorksheetKit/        cells, .wxm and .wxmx read/write
    maxima-spike/        Phase 0 command-line spike
  App/Macsima/           SwiftUI shell + worksheet view
  Resources/lisp/        wxMathML.lisp, unmodified, notices kept (GPL)
  docs/
    BOOTSTRAP.md         this document
    WXMX_COMPAT.md       compatibility ledger
    PHASE0_REPORT.md     what the real Maxima showed
  Tests/
    Fixtures/transcripts/   49 captured sessions, README, record.sh
    Fixtures/wxmx/          sample .wxmx files, including your own
  Scripts/               packaging scripts, added only if you share the app
```

### Phase 0 spike (first sketch, superseded)

This first sketch did not survive Swift 6 strict concurrency. The working spike is Sources/maxima-spike in the repo: one serial queue, an explicit 127.0.0.1 bind, and posix\_spawn with POSIX\_SPAWN\_SETPGROUP. The sketch is kept for reference only. It listens on loopback, spawns Maxima with `-s`, accepts the control connection and prints whatever arrives. Without the glue Lisp, Maxima answers in plain text, which is exactly what you want to record first. Point it at /opt/homebrew/bin/maxima.

```swift
import Foundation
import Network

final class MaximaSpike {
    private var listener: NWListener!
    private var conn: NWConnection?
    // MAXIMA_AUTH_CODE: a long random token, checked later against the echoed <wxxml-key>.
    let token = (0..<64).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()

    func run(maxima: URL) throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: .any)      // port chosen by the OS
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let self,
                  let port = self.listener.port?.rawValue else { return }
            self.launch(maxima: maxima, port: port)
        }
        listener.start(queue: .global())
    }

    private func launch(maxima: URL, port: UInt16) {
        let p = Process()
        p.executableURL = maxima
        p.arguments = ["-s", String(port)]              // Maxima is the client of this socket
        var env = ProcessInfo.processInfo.environment
        env["MAXIMA_AUTH_CODE"] = token
        p.environment = env
        // Production: posix_spawn with POSIX_SPAWN_SETPGROUP so the whole group can be killed.
        try? p.run()
    }

    private func accept(_ c: NWConnection) {
        guard conn == nil else { c.cancel(); return }   // a second connection would be the interrupt channel
        conn = c
        c.start(queue: .global())
        receive(c)
        send("integrate(sin(x), x);\n")
    }

    private func send(_ s: String) {
        conn?.send(content: s.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            if let data { print(String(decoding: data, as: UTF8.self), terminator: "") }
            if !done && err == nil { self?.receive(c) }
        }
    }
}
```

### First-week checklist

- [ ] Confirm your Homebrew Maxima (5.50.0, SBCL) runs: `maxima --version`
- [ ] Run the spike and record raw transcripts for about 20 representative commands (plain result, `$`-terminated, error, `asksign` question, long `integrate` with interrupt, a `plot2d`)
- [ ] Send the glue Lisp with `:lisp-quiet` and record the tagged XML for the same commands
- [ ] Write the tag scanner against those fixtures, feeding it random chunk boundaries
- [ ] Check that wx-open-interrupt-channel works with Homebrew's SBCL by interrupting a long integrate
- [ ] Add the GPL-2.0-or-later LICENSE file and a docs/WXMX\_COMPAT.md stub

## Sources

Read in full (as of 2026-10-14):

- [wxMaxima repository README](https://github.com/wxMaxima-developers/wxmaxima)
- [Maxima.cpp](https://raw.githubusercontent.com/wxMaxima-developers/wxmaxima/main/src/Maxima.cpp), [MaximaProcessManager.cpp](https://raw.githubusercontent.com/wxMaxima-developers/wxmaxima/main/src/MaximaProcessManager.cpp), [MaximaEvaluator.cpp](https://raw.githubusercontent.com/wxMaxima-developers/wxmaxima/main/src/MaximaEvaluator.cpp), [MaximaInterruptChannel.cpp](https://raw.githubusercontent.com/wxMaxima-developers/wxmaxima/main/src/MaximaInterruptChannel.cpp), [MaximaProtocol.h](https://raw.githubusercontent.com/wxMaxima-developers/wxmaxima/main/src/MaximaProtocol.h)
- [wxMathML.lisp](https://raw.githubusercontent.com/wxMaxima-developers/wxmaxima/main/src/wxMathML.lisp) (the file was cut off near its end; the asynchronous-output section was the last part I saw)
- [Compiling.md](https://raw.githubusercontent.com/wxMaxima-developers/wxmaxima/main/Compiling.md)
- [wxMaxima release Version-26.07.1](https://github.com/wxMaxima-developers/wxmaxima/releases/tag/Version-26.07.1)
- [Maxima installation page](https://maxima.sourceforge.io/download.html) and [Maxima versions page](https://maxima.sourceforge.io/versions.html)

Search excerpts only (not opened in full):

- Maxima man page: [`-s` option](https://manpages.ubuntu.com/manpages/noble/man1/maxima.1.html)
- Maxima mailing list: [2008, wxMaxima socket on port 4010](https://maxima.sourceforge.io/ext/list_archives/2008/msg01120.html), [2011, building Maxima.app](https://maxima.sourceforge.io/ext/list_archives/2011/msg00154.html), [2012, MLABLE to MLABEL](https://maxima.sourceforge.io/ext/list_archives/2012/msg03489.html), [2012, broken 5.28.0 DMG](https://maxima.sourceforge.io/ext/list_archives/2012/msg04027.html), [2003, gnuplot and the GPL](https://maxima.sourceforge.io/ext/list_archives/2003/msg00968.html)
- [MacPorts ticket 67801, SBCL and ARM64](https://trac.macports.org/ticket/67801)
- [Apple, Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime) and an [Apple developer forum thread on JIT and notarization](https://developer.apple.com/forums/thread/667527)
- [SBCL licensing](https://sbcl.org/history.html) and [gnuplot copyright file](https://metadata.ftp-master.debian.org/changelogs/main/g/gnuplot/stable_copyright)
- [wxMaxima Doxygen: class Maxima](https://wxmaxima-developers.github.io/wxmaxima/Doxygen-documentation/classMaxima.html)

Not sourced: the effort estimates, the Swift sketch, and the notes on `posix_spawn`, WebKit's MathML support and the macOS 26 SwiftUI features (rich-text editor, WebView) mentioned above. The Homebrew formula details come from its formula page, read on 2026-10-18.
