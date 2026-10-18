// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// A worksheet file. Placeholder until `.wxmx` reading and writing exist.
public final class WorksheetDocument: ReferenceFileDocument {
    public static let readableContentTypes: [UTType] = [.wxmx]

    public init() {}

    public required init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    public func snapshot(contentType: UTType) throws -> Data { Data() }

    public func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteUnknown)
    }
}

struct WorksheetWindow: View {
    let document: WorksheetDocument

    var body: some View {
        Text("Macsima: worksheet editor coming in Phase 2.")
            .frame(minWidth: 480, minHeight: 320)
    }
}
