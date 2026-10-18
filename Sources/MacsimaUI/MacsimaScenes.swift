// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// wxMaxima's zipped XML worksheet. wxMaxima declares only the extension,
    /// so this app imports the type under wxMaxima's bundle prefix.
    public static let wxmx = UTType(importedAs: "net.sf.wxmaxima.wxmx")
}

/// The app's scenes: one document window per worksheet.
public struct MacsimaScenes: Scene {
    public init() {
        #if DEBUG
        Task { @MainActor in KeyScriptDriver.startIfRequested() }
        #endif
    }

    public var body: some Scene {
        DocumentGroup(newDocument: { WorksheetDocument(worksheet: DemoWorksheet.requested ? DemoWorksheet.make() : .empty()) }) { file in
            WorksheetWindow(document: file.document)
        }
        .defaultSize(width: 900, height: 980)
        .commands { WorksheetCommands() }
        Settings { SettingsView() }
    }
}
