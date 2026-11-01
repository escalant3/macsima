# Macsima

A native macOS front end for [Maxima](https://maxima.sourceforge.io), the computer algebra system, written in
Swift. It opens and saves wxMaxima's worksheets, so it works as a drop-in replacement for wxMaxima on Apple
silicon Macs, and you can keep sharing worksheets with people who use wxMaxima on any platform.

Macsima is in early development. It works in day-to-day work, and it aims at full feature parity with wxMaxima.
[`docs/PARITY.md`](docs/PARITY.md) tracks the gaps openly.

## Why Macsima

- **A native Mac app.** It's built with SwiftUI and AppKit, so it has native windows, menus, keyboard shortcuts,
  Find and Replace, undo, dark mode and Settings.
- **Typeset math with crisp fonts.** Outputs are typeset as proper 2D math and stay sharp on Retina displays.
  Long results break across lines. Plots are drawn at 2x resolution or as SVG.
- **wxMaxima compatible.** Macsima reads and writes `.wxmx` and `.wxm` files. Anything it can't show yet is kept
  and saved back unchanged, so a worksheet can go back and forth between Macsima and wxMaxima without losing data.
  [`docs/WXMX_COMPAT.md`](docs/WXMX_COMPAT.md) lists every element and its status.
- **Few dependencies.** You need Maxima and gnuplot, and nothing else: no wxWidgets and no extra toolkits.

## Requirements

- macOS 26 (Tahoe) on Apple silicon
- Maxima from Homebrew, the SBCL build: `brew install maxima`
- gnuplot, for plots: `brew install gnuplot`

If Maxima or gnuplot live somewhere else, you can set their paths in Settings.

## Install

Download `Macsima-<version>.dmg` from [the website](https://escalant3.github.io/macsima/) or
[Releases](https://github.com/escalant3/macsima/releases), open it and
drag Macsima to Applications. Macsima updates itself: Macsima › Check for Updates…, or automatically once you
allow it. Releasing is described in [`docs/RELEASING.md`](docs/RELEASING.md).

## Build and run

Building needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). From the
repository root:

    xcodegen generate
    xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode build
    open .build/xcode/Build/Products/Debug/Macsima.app

At launch you get an Open panel, as with most document apps. Click New Document for an empty worksheet, or pick
a `.wxmx` or `.wxm` file. Cmd+N also opens a new worksheet.

To open your existing files, use File › Open in Macsima, or right-click a file › Open With › Macsima.
Double-clicking a `.wxmx` still opens wxMaxima if it is your default app. macOS autosaves open worksheets in
place, so open a copy if the original must stay exactly as it is.

To see every cell and output kind, open the demo worksheet:

    open .build/xcode/Build/Products/Debug/Macsima.app --args -MacsimaDemoWorksheet YES

The [manual](docs/MANUAL.md) covers everything else.

## Keys

| Key | Action |
| --- | --- |
| Shift+Return | Evaluate the cell |
| Cmd+R | Evaluate all cells |
| Cmd+. | Interrupt |
| Cmd+0 / 1 / 2 / 3 / 4 | Insert a code / text / title / section / subsection cell |
| Cmd+Shift+Delete | Delete the cell |
| Up / Down on the first / last line | Move to the previous / next cell |
| Cmd+/ | Comment or uncomment the lines |
| Cmd+F / Cmd+Opt+F | Find / Find and Replace across the worksheet |
| Cmd+G / Cmd+Shift+G / Cmd+E | Next / previous match / find the selection |
| Cmd+plus, Cmd+= / Cmd+- | Zoom in / out (saved in the file) |
| Cmd+Z | Undo |
| Cmd+S | Save |

The Cell, Maxima and View menus list the same actions, plus Change Cell Type, Restart Maxima and Actual Size.

Things to know:

- Each window starts its own Maxima, which takes about half a second. The toolbar shows "Ready" when it's up.
  Closing the window stops it.
- Click a math output to make it selectable. Right-click it to copy it as Maxima input, LaTeX, MathML or a picture.
- Anything Macsima keeps from a file but can't show yet appears as a gray placeholder or in a banner. It is
  saved back unchanged.

## Tests

    swift build
    swift test                             # read the "Test run with N tests" line
    Tests/Fixtures/keyscripts/run.sh eval-basics   # key scripts drive the debug app
    xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode \
        -destination 'platform=macOS' test # XCUITests: real keystrokes, take over keyboard and mouse

See `Tests/UITests/README.md` for what the UI tests need.

The engine tests run against a real Maxima process. File compatibility is tested both ways:

- wxMaxima's own sample worksheets must survive a read and write in Macsima unchanged.
- Worksheets that Macsima writes are opened, evaluated and re-saved by wxMaxima, then read back by Macsima.

## Acknowledgments

Macsima exists because of [wxMaxima](https://github.com/wxMaxima-developers/wxmaxima) and the wxMaxima team and
contributors. Their work is the reference for everything Macsima does, and parts of it are used directly:

- `Sources/MaximaKit/Resources/wxMathML.lisp`, wxMaxima's Lisp that connects Maxima to the front end, is used
  unchanged.
- Some code is ported from wxMaxima's C++ sources, including the `.wxm` format, message explanations and input
  text handling. Each ported file keeps its original copyright notices.
- wxMaxima's sample worksheets and test files (`Tests/Fixtures/wxmx/wxmaxima-samples/` and `Tests/Fixtures/wxm/`)
  are included unchanged, as the yardstick for file compatibility. Some unit tests port wxMaxima's own test cases.
- The built-in command templates for completion come from wxMaxima.

Thanks also to the [Maxima](https://maxima.sourceforge.io) developers, and to [gnuplot](http://www.gnuplot.info).

## License

GPL-2.0-or-later (see `LICENSE`). Files that come from or are ported from wxMaxima keep their own notices, also
GPL-2.0-or-later.
