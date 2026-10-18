# Macsima

A native macOS front end for [Maxima](https://maxima.sourceforge.io), written in Swift. A personal tool aiming,
in stages, at feature parity with wxMaxima. Status: Phase 0 (feasibility spike). See `docs/BOOTSTRAP.md`
and `docs/PHASE0_REPORT.md`.

Requires macOS 26 on Apple Silicon, Homebrew Maxima (`brew install maxima`, SBCL build) and gnuplot.

    swift build
    swift run maxima-spike        # spawn Maxima, send integrate(sin(x), x); print raw bytes
    # Command Line Tools only (no Xcode): plain `swift test` runs zero tests; use
    swift test -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks

License: GPL-2.0-or-later (see `LICENSE`). `Resources/lisp/wxMathML.lisp` is from wxMaxima, with its own notices.
