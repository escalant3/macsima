// SPDX-License-Identifier: GPL-2.0-or-later

import Sparkle
import SwiftUI

/// Sparkle's updater (docs/RELEASING.md). It lives in the app target, not in
/// MacsimaUI, so the package's tests and tools never link Sparkle.
/// Debug builds never start it: key scripts and UI tests must not see its dialogs.
@MainActor @Observable
final class Updater {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheck = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func check() { controller.checkForUpdates(nil) }
}

/// Macsima › Check for Updates…
struct UpdateCommands: Commands {
    let updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.check() }
                .disabled(!updater.canCheck)
        }
    }
}
