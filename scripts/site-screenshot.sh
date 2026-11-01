#!/bin/zsh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Retakes the website's screenshots (site/screenshot-light.png and -dark.png)
# from the Debug app with the site-screenshot key script, then crops them.
# Needs Screen Recording permission for the terminal that runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode build -quiet
Tests/Fixtures/keyscripts/run.sh site-screenshot
for mode in light dark; do
  shot=.build/keyscripts/site-$mode.png
  [[ -f $shot ]] || { echo "no $shot: give the terminal Screen Recording permission" >&2; exit 1; }
  swift scripts/crop-screenshot.swift $shot site/screenshot-$mode.png
done
