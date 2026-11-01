#!/bin/zsh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds the Release app and packs it into .build/release/Macsima-<version>.dmg.
# See docs/RELEASING.md for the whole release, including notarization.
#
#   scripts/make-dmg.sh                          ad-hoc signed, for local tries
#   SIGN_IDENTITY="Developer ID Application: …" scripts/make-dmg.sh
#                                                signed for notarization
#
# The version and Sparkle settings come from project.yml. For a test build,
# SPARKLE_FEED_URL and SPARKLE_PUBLIC_KEY in the environment override them.
set -euo pipefail
cd "$(dirname "$0")/.."

identity=${SIGN_IDENTITY:--}
derived=.build/xcode-release
out=.build/release

overrides=()
[[ -n ${SPARKLE_FEED_URL:-} ]] && overrides+=("SPARKLE_FEED_URL=$SPARKLE_FEED_URL")
[[ -n ${SPARKLE_PUBLIC_KEY:-} ]] && overrides+=("SPARKLE_PUBLIC_KEY=$SPARKLE_PUBLIC_KEY")

xcodegen generate >/dev/null
xcodebuild -project Macsima.xcodeproj -scheme Macsima -configuration Release \
  -derivedDataPath $derived $overrides build -quiet

built=$derived/Build/Products/Release/Macsima.app
plist() { /usr/libexec/PlistBuddy -c "Print $1" $built/Contents/Info.plist }
version=$(plist CFBundleShortVersionString)
build=$(plist CFBundleVersion)
if [[ -z $(plist SUPublicEDKey) ]]; then
  echo "SPARKLE_PUBLIC_KEY is empty in project.yml: the app could never check for updates (docs/RELEASING.md)." >&2
  exit 1
fi

rm -rf $out/stage && mkdir -p $out/stage
ditto $built $out/stage/Macsima.app
app=$out/stage/Macsima.app
sparkle=$app/Contents/Frameworks/Sparkle.framework

# The app is not sandboxed, so Sparkle's XPC services are not needed.
rm -rf $sparkle/XPCServices $sparkle/Versions/B/XPCServices

# Inside out, as Sparkle's documentation says (never --deep). A Developer ID
# needs the hardened runtime and a secure timestamp for notarization.
flags=(--force --sign $identity)
[[ $identity != - ]] && flags+=(--options runtime --timestamp)
codesign $flags $sparkle/Versions/B/Autoupdate
codesign $flags $sparkle/Versions/B/Updater.app
codesign $flags $sparkle
codesign $flags $app
codesign --verify --deep --strict $app

# Drag-to-install image: the app and a link to /Applications.
ln -s /Applications $out/stage/Applications
dmg=$out/Macsima-$version.dmg
rm -f $dmg
hdiutil create -quiet -volname "Macsima $version" -srcfolder $out/stage -fs APFS -format UDZO $dmg
[[ $identity != - ]] && codesign --force --sign $identity --timestamp $dmg
rm -rf $out/stage

echo "$dmg  (version $version, build $build, signed with ${identity/#-/ad-hoc})"
