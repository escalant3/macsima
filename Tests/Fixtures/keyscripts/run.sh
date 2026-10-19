#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Runs a key script against the Debug app and checks its dumps.
# Usage (repository root, after xcodebuild): Tests/Fixtures/keyscripts/run.sh editor-basics [file.wxmx]
# With a file, a copy of it (.build/keyscripts/<script>.wxmx) is opened instead of a new worksheet.
# The app is activated with an Apple Event; key events are synthesized inside
# the app (KeyScriptDriver), so no Accessibility permission is needed. The
# display is kept awake: a sleeping display makes the window inactive.
set -eu
name=$1
app=.build/xcode/Build/Products/Debug/Macsima.app/Contents/MacOS/Macsima
mkdir -p .build/keyscripts
rm -f .build/keyscripts/"${name%%-*}"-*.json
open_file=""
if [ $# -gt 1 ]; then
  cp "$2" ".build/keyscripts/$name.wxmx"
  open_file="$PWD/.build/keyscripts/$name.wxmx"
fi
caffeinate -u -t 1
"$app" $open_file -ApplePersistenceIgnoreState YES -MacsimaKeyScript "Tests/Fixtures/keyscripts/$name.keys" 2>".build/keyscripts/$name.log" &
pid=$!
caffeinate -d -i -w $pid &
sleep 1
# The app may take a moment to register; try for a few seconds.
for _ in 1 2 3 4 5; do
  osascript -e 'tell application "Macsima" to activate' >/dev/null 2>&1 && break
  sleep 1
done
for _ in $(seq 1 120); do sleep 1; kill -0 $pid 2>/dev/null || break; done
kill $pid 2>/dev/null || true
grep "lost focus" ".build/keyscripts/$name.log" >&2 || true
python3 "Tests/Fixtures/keyscripts/check.py" "$name"
