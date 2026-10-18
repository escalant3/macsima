// SPDX-License-Identifier: GPL-2.0-or-later

import MacsimaUI
import SwiftUI

@main
struct MacsimaApp: App {
    @NSApplicationDelegateAdaptor(MacsimaAppDelegate.self) private var delegate

    var body: some Scene {
        MacsimaScenes()
    }
}
