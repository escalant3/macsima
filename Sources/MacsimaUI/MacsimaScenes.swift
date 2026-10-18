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
    public init() {}

    public var body: some Scene {
        DocumentGroup(newDocument: { WorksheetDocument() }) { file in
            WorksheetWindow(document: file.document)
        }
    }
}
