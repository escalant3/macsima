# Releasing

Macsima ships as a drag-to-install DMG on GitHub Releases, signed with a Developer ID and notarized. Installed
copies update themselves with [Sparkle](https://sparkle-project.org) 2.10.0 (MIT): Macsima › Check for Updates…,
and Sparkle checks on its own once a day after asking the user on the second launch. There is no App Store build.

The DMG holds only Macsima. Maxima and gnuplot still come from Homebrew (`brew install maxima gnuplot`), as
CLAUDE.md decides; Macsima never bundles them.

## How updates work

- `SUFeedURL` is `https://github.com/escalant3/macsima/releases/latest/download/appcast.xml`, so the feed is the
  `appcast.xml` attached to the release GitHub marks as latest. Every release must attach a fresh one, and the
  repository (or at least its releases) must be public.
- Sparkle installs an update only if its EdDSA signature matches `SUPublicEDKey` and the new app is signed by the
  same Developer ID team as the installed one.
- The app is not sandboxed, so `scripts/make-dmg.sh` removes Sparkle's XPC services and signs the rest inside out
  (Sparkle's documentation; never `--deep`).
- Debug builds never start the updater, so key scripts and UI tests never see its dialogs. The menu item is there
  but disabled.

Tested on 2026-11-01 with a throwaway key, a separate bundle id and a feed on `127.0.0.1`: a 0.3 build signed
with the Apple Development certificate and the hardened runtime found 0.4, downloaded it, installed it on quit
and launched as 0.4 with Maxima running. Not tested: a Developer ID signature, notarization, Gatekeeper on a
downloaded DMG, and the GitHub-hosted feed.

## One-time setup

1. **Build once** so Sparkle's tools are on disk:

       scripts/make-dmg.sh

   It stops with "SPARKLE_PUBLIC_KEY is empty" until step 2 is done; the tools are there anyway. The commands
   below call them through `sparkle=.build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin`.

2. **EdDSA key.** This stores the private key in your login keychain and prints the public key:

       sparkle=.build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin
       $sparkle/generate_keys

   Put the public key in `project.yml` as `SPARKLE_PUBLIC_KEY` and commit it. Back up the private key somewhere
   safe outside the repository (`$sparkle/generate_keys -x <file>`): without it, installed copies can never be
   updated again.

3. **Notary credentials**, with an app-specific password from account.apple.com:

       xcrun notarytool store-credentials macsima-notary --apple-id <your Apple ID> --team-id <TEAM_ID>

4. **Signing identity.** `security find-identity -v -p codesigning` shows its full name,
   `Developer ID Application: <name> (<TEAM_ID>)`.

## Each release

Set the version once, the same value as `MARKETING_VERSION`:

    version=0.3

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (the build number must grow every
   time; Sparkle compares it) and commit.
2. Build, sign and verify:

       SIGN_IDENTITY="Developer ID Application: <name> (<TEAM_ID>)" scripts/make-dmg.sh

3. Notarize and staple. Do this before step 4: stapling changes the DMG, and Sparkle's signature must cover the
   final file.

       xcrun notarytool submit .build/release/Macsima-$version.dmg --keychain-profile macsima-notary --wait
       xcrun stapler staple .build/release/Macsima-$version.dmg
       spctl --assess --type open --context context:primary-signature -v .build/release/Macsima-$version.dmg

4. Update the appcast. `generate_appcast` signs the DMG with the key in your keychain and keeps the entries
   already in the folder's `appcast.xml`. If `.build/release/updates` is gone, first download the current
   `appcast.xml` from the latest release into it. Release notes go next to the DMG as `Macsima-$version.md`.

       mkdir -p .build/release/updates
       cp .build/release/Macsima-$version.dmg .build/release/updates/
       $sparkle/generate_appcast --download-url-prefix \
           https://github.com/escalant3/macsima/releases/download/v$version/ .build/release/updates

5. Tag and publish. Attach both files, and don't mark the release as a pre-release (the feed follows "latest"):

       git tag v$version && git push origin v$version
       gh release create v$version .build/release/Macsima-$version.dmg .build/release/updates/appcast.xml \
           --title "Macsima $version" --notes-file .build/release/updates/Macsima-$version.md

6. Check: an installed older copy finds the update under Macsima › Check for Updates…

## Licenses

The DMG distributes GPL-2.0-or-later binaries. The tagged source on GitHub is the corresponding source; the
release notes should link to the tag. Sparkle and ZIPFoundation are MIT.
