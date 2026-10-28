#!/bin/zsh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Brings App/Macsima/Localizable.xcstrings up to date with the source:
# builds the app (which makes the compiler list every localizable string,
# in MacsimaUI and the kits too), then merges that list into the catalog.
# New strings are added untranslated; strings no longer used are marked stale.
# See docs/LOCALIZATION.md.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate >/dev/null
# SWIFT_EMIT_LOC_STRINGS reaches the package targets only from the command
# line. A separate build folder keeps the usual one from rebuilding afterwards.
xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode-strings \
  SWIFT_EMIT_LOC_STRINGS=YES build -quiet

intermediates=.build/xcode-strings/Build/Intermediates.noindex/Macsima.build/Debug
stringsdata=()
for target in Macsima MacsimaUI MaximaKit WorksheetKit; do
  stringsdata+=($intermediates/$target.build/Objects-normal/arm64/*.stringsdata(N))
done
stringsdata=(${stringsdata:#*ExtractedAppShortcutsMetadata.stringsdata})
(( ${#stringsdata} )) || { echo "no .stringsdata found under $intermediates" >&2; exit 1; }

for catalog in App/Macsima/Localizable.xcstrings; do
  xcrun xcstringstool sync "$catalog" --stringsdata $stringsdata
done
echo "Synced ${#stringsdata} files into App/Macsima/Localizable.xcstrings."
