# UI tests (XCUITest)

Real keystrokes against the Debug app. Phase 3 added these next to the key-script driver (`Tests/Fixtures/keyscripts/`), which stays.

Run from the repository root:

    xcodegen generate
    xcodebuild -project Macsima.xcodeproj -scheme Macsima -derivedDataPath .build/xcode -destination 'platform=macOS' test

One-time setup on this Mac (done 2026-10-19), in a real Terminal window because `sudo` needs a password:

    sudo DevToolsSecurity -enable
    sudo automationmodetool enable-automationmode-without-authentication

While the tests run they take over the keyboard and mouse; don't type.

Safety: the app is launched with `-ApplePersistenceIgnoreState YES -MacsimaUITest YES`. With that flag, `TestGuard` closes everything and quits if a document outside `.build/` is open, so a test never types into your own worksheets. Tests start from an untitled worksheet and the app is terminated without saving.

Elements are found by accessibility identifier: `cell-input-N` (the editor of cell N), `cell-output-N-M` (output M of cell N; math outputs carry their plain-text form as the label) and `session-state` (the toolbar state).
