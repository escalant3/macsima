// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import MaximaKit

/// Installs the orphan guard at launch and shuts every Maxima down before
/// the app quits, so quitting never leaves a Maxima process behind.
@MainActor
public final class MacsimaAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationWillFinishLaunching(_ notification: Notification) {
        // Start with an untitled worksheet, as wxMaxima does, instead of
        // macOS's Open panel; untitled worksheets are saved later with Cmd+S.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        OrphanGuard.install()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let controllers = WorksheetController.all
        guard !controllers.isEmpty else { return .terminateNow }
        Task { @MainActor in
            for controller in controllers { await controller.shutdown() }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
