# Macsima

A native macOS front end for [Maxima](https://maxima.sourceforge.io), written in Swift. A personal tool aiming,
in stages, at feature parity with wxMaxima. Status: Phase 3 (daily driver) in progress. See `docs/BOOTSTRAP.md`
for the plan, `docs/PARITY.md` for where it stands against wxMaxima, and the `docs/PHASE*_REPORT.md` files.

Requires macOS 26 on Apple Silicon, Homebrew Maxima (`brew install maxima`, SBCL build), gnuplot, Xcode and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build and run

From the repo root:

    xcodegen generate
    xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode build
    open .build/xcode/Build/Products/Debug/Macsima.app

At launch you get an Open panel, as with most document apps. Click New Document for an empty worksheet, or pick
a `.wxmx` file. Cmd+N also opens a new worksheet.

Ways to try it:

- Your own files: double-clicking a `.wxmx` in Finder still opens wxMaxima, since Macsima isn't the default. Use
  File › Open in Macsima, or right-click the file › Open With › Macsima. macOS autosaves open worksheets in place,
  so open a copy if the original must stay exactly as it is.
- Example files: the sessions in `Tests/Fixtures/wxmx/macsima-written/` and wxMaxima's samples in
  `Tests/Fixtures/wxmx/wxmaxima-samples/`. Open copies, because the tests depend on these files.
- A ready-made worksheet with every cell and output kind:

      open .build/xcode/Build/Products/Debug/Macsima.app --args -MacsimaDemoWorksheet YES

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
Settings (Cmd+,) has the Maxima path.

Things to know:

- Each window starts its own Maxima, which takes about half a second; the toolbar shows "Ready" when it's up.
  Closing the window stops it.
- Clicking a math output makes it selectable; right-click it to copy it as text or MathML.
- Things Macsima keeps from a file but can't show yet appear as gray placeholders or in a banner, and they are
  saved back unchanged.

## Tests

    swift build
    swift test                             # read the "Test run with N tests" line
    Tests/Fixtures/keyscripts/run.sh eval-basics   # key scripts drive the debug app
    xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode \
        -destination 'platform=macOS' test # XCUITests: real keystrokes, take over keyboard and mouse

See `Tests/UITests/README.md` for what the UI tests need.

License: GPL-2.0-or-later (see `LICENSE`). `Sources/MaximaKit/Resources/wxMathML.lisp` is from wxMaxima, with its
own notices, and so is code ported from wxMaxima, as noted in each file.
