#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Records every scenario in scenarios/ into raw/ (no glue) and glue/ (wxMathML.lisp).
# A scenario named NAME.raw.scn or NAME.glue.scn runs only in that mode.
# Usage: Tests/Fixtures/transcripts/record.sh   (from the repository root, after swift build)
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
spike="$here/../../../.build/debug/maxima-spike"
lisp="$here/../../../Sources/MaximaKit/Resources/wxMathML.lisp"
for mode in raw glue; do
  mkdir -p "$here/$mode"
  for scn in "$here"/scenarios/*.scn; do
    base=$(basename "$scn" .scn)
    case "$base" in
      *.raw)  [ "$mode" = raw ]  || continue; base=${base%.raw} ;;
      *.glue) [ "$mode" = glue ] || continue; base=${base%.glue} ;;
    esac
    echo "== $mode/$base" >&2
    if [ "$mode" = glue ]; then
      "$spike" record "$scn" "$here/$mode/$base" --glue "$lisp"
    else
      "$spike" record "$scn" "$here/$mode/$base"
    fi
    # Keep the child's stdout/stderr log only when it has something in it.
    [ -s "$here/$mode/$base.stdio.txt" ] || rm -f "$here/$mode/$base.stdio.txt"
  done
done
