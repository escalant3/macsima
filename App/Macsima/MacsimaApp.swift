// SPDX-License-Identifier: GPL-2.0-or-later

import MacsimaUI
import SwiftUI

@main
struct MacsimaApp: App {
    @NSApplicationDelegateAdaptor(MacsimaAppDelegate.self) private var delegate
    @State private var updater = Updater()

    var body: some Scene {
        MacsimaScenes()
            .commands { UpdateCommands(updater: updater) }
    }
}
