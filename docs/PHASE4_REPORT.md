# Phase 4 report: sharing

2026-11-01 · macOS 26.5.1 (arm64) · Xcode 26.6, Swift 6.3.3 · Homebrew Maxima 5.50.0 on SBCL 2.6.9 · Sparkle 2.10.0

**Result: Phase 4 is done.** Macsima 0.3 is on [GitHub Releases](https://github.com/escalant3/macsima/releases/tag/v0.3) as a Developer ID signed, notarized DMG that updates itself with Sparkle. A download page is live at https://escalant3.github.io/macsima/.

## Summary

- **Default math size 16** instead of 19 (Settings › Math size).
- **A DMG.** `scripts/make-dmg.sh` builds the Release app, signs it inside out and packs a drag-to-install DMG. Without `SIGN_IDENTITY` it signs ad-hoc, for local tries. With a Developer ID it adds the hardened runtime and a secure timestamp, ready for notarization.
- **Updates.** Sparkle 2.10.0 in the app target only, so the package's tests and tools never link it. Macsima › Check for Updates…, and a daily check once the user allows it. Debug builds never start the updater, so key scripts and UI tests never see its dialogs.
- **Versions** live in `project.yml` as `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; Sparkle compares the build number.
- **Releasing** is written down step by step in [RELEASING.md](RELEASING.md): the one-time setup (EdDSA key, notary credentials, signing identity), then build, notarize, staple, appcast, tag and publish. The owner runs the signing and notarization commands.
- **The website** (`site/`) is one page published by `.github/workflows/pages.yml` whenever `site/` changes on `main`. It asks GitHub's API for the latest release when it loads, so a release needs no change to the site. Without the API, the button falls back to the latest release page.
- **The website's screenshot** is retaken with `scripts/site-screenshot.sh`: the `site-screenshot` key script (a title and four typeset results, no errors) in light and dark, cropped by `scripts/crop-screenshot.swift`.
- **Tests:** 183 Swift Testing tests in 43 suites pass (`swift test`). The new key script `site-screenshot` passes. The UI tests were not rerun: no UI code changed apart from the new menu item.

## Decisions

- **Sparkle** rather than a home-made checker: it is the usual updater for Mac apps outside the App Store, MIT-licensed, and checks both the Developer ID and its own EdDSA signature on every update. 2.10.0 rather than 2.10.1, which was a week old.
- **No bundled Maxima.** The DMG holds only Macsima; Maxima and gnuplot come from Homebrew, as CLAUDE.md decides. BOOTSTRAP.md's Shipping later steps 2 to 6 stay deferred.
- **GitHub Releases** host the DMGs and the appcast; the feed URL is `releases/latest/download/appcast.xml`, so every release attaches a fresh `appcast.xml`.
- **No App Store, no sandbox.** Sparkle's XPC services are removed from the bundle, as Sparkle allows for apps that are not sandboxed.

## How it was tested

- **An update, locally** (before the release): two builds, 0.3 and 0.4, under a separate bundle id so the user's settings were untouched, signed with the Apple Development certificate and the hardened runtime as a stand-in for Developer ID, with a throwaway EdDSA key and a feed on `127.0.0.1`. The 0.3 app found 0.4, downloaded it, installed it on quit and launched as 0.4 with Maxima running. The test's defaults domain, cache and server were removed afterwards.
- **The hardened runtime** does not stop Macsima from starting Maxima: no entitlements are needed, since Maxima is a separate Homebrew binary.
- **Release 0.3, from outside:** the feed resolves from GitHub; the downloaded DMG is byte-for-byte the notarized one, matches the appcast's length, and its EdDSA signature verifies against `SUPublicEDKey` (checked with CryptoKit, not Sparkle); Gatekeeper accepts it as `Notarized Developer ID` with the ticket stapled.
- **The website:** checked locally and live in light, dark and at phone width (375 px, no sideways scrolling); the button resolves to `Macsima-0.3.dmg`.

## Problems found and fixed on the way

- **Release notes link.** `generate_appcast` linked 0.3's notes to `releases/latest/download/Macsima-0.3.md`, which is not a release asset (404) and would point at the wrong release once 0.4 is out. Releases now use `--embed-release-notes`; the broken link was removed from the local appcast that 0.4's will build on. The published 0.3 appcast still has it, which is harmless: Sparkle only shows notes for an update it offers.
- **Screen Recording.** Key-script screenshots fail from a session without Screen Recording permission ("could not create image from window"); `scripts/site-screenshot.sh` runs in the owner's Terminal.
- **`Package.resolved` churn.** Xcode builds add a Sparkle pin to the root `Package.resolved` and `swift build` removes it again. Don't commit that change.

## What differed from BOOTSTRAP.md (updated there)

- BOOTSTRAP.md planned Phase 4 as optional, with a notarized DMG and a bundled Maxima only if people asked. Phase 4 ships the DMG without Maxima, adds Sparkle updates, and rules out the App Store. The Purpose, Shipping later and Roadmap sections, CLAUDE.md and the README say so.
- The layout's `Scripts/` folder is `scripts/` (`update-strings.sh`, `make-dmg.sh`, `site-screenshot.sh`, `crop-screenshot.swift`).

## Still untested

- **A real update from GitHub,** 0.3 to a newer release. It needs a second release; keep `.build/release/updates` until then.
- **A Mac other than the owner's,** in particular one without Homebrew Maxima: what a new user sees at first launch when Maxima is missing.
- **Sparkle's prompt** on the second launch, asking whether to check automatically.
- **`scripts/make-dmg.sh` with spaces** in the repository path.
