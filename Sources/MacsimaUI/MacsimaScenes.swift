// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import UniformTypeIdentifiers
import WorksheetKit

extension UTType {
    /// wxMaxima's zipped XML worksheet. wxMaxima declares only the extension,
    /// so this app imports the type under wxMaxima's bundle prefix.
    public static let wxmx = UTType(importedAs: "net.sf.wxmaxima.wxmx")
    /// wxMaxima's plain-text batch worksheet (inputs only, no outputs).
    public static let wxm = UTType(importedAs: "net.sf.wxmaxima.wxm", conformingTo: .plainText)
    /// A Maxima batch file, for File › Export.
    public static let maximaBatch = UTType(filenameExtension: "mac", conformingTo: .plainText) ?? .plainText
}

/// The app's scenes: one document window per worksheet.
public struct MacsimaScenes: Scene {
    /// A new worksheet at Settings' default zoom.
    nonisolated static func newWorksheet() -> Worksheet {
        var sheet = DemoWorksheet.requested ? DemoWorksheet.make() : .empty()
        sheet.zoom = AppSettings.defaultZoom
        return sheet
    }

    public init() {
        #if DEBUG
        Task { @MainActor in
            KeyScriptDriver.startIfRequested()
            TestGuard.startIfUITest()
        }
        #endif
    }

    public var body: some Scene {
        DocumentGroup(newDocument: { WorksheetDocument(worksheet: Self.newWorksheet()) }) { file in
            WorksheetWindow(document: file.document)
        }
        .defaultSize(width: 900, height: 980)
        .commands { WorksheetCommands() }
        Settings { SettingsView() }
    }
}
