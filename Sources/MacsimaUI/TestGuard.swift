// SPDX-License-Identifier: GPL-2.0-or-later

#if DEBUG
import AppKit

/// Keeps automated runs (key scripts, UI tests) away from the user's own
/// worksheets: only untitled worksheets and files under `.build/` may be open.
@MainActor
enum TestGuard {
    /// True when the app was launched by the UI tests (`-MacsimaUITest YES`).
    static var isUITest: Bool { UserDefaults.standard.bool(forKey: "MacsimaUITest") }

    /// Open documents outside `allowed` (a path fragment such as `/.build/`).
    static func foreignDocuments(allowed: String) -> [URL] {
        NSDocumentController.shared.documents.compactMap(\.fileURL).filter { !$0.path.contains(allowed) }
    }

    /// Closes every document without saving and quits when a document outside
    /// `allowed` is open (a restored window, say). Returns true if it did.
    static func refuseIfForeign(allowed: String, log: (String) -> Void) -> Bool {
        let foreign = foreignDocuments(allowed: allowed)
        guard !foreign.isEmpty else { return false }
        log("refusing to run: open documents outside \(allowed): \(foreign.map(\.path))")
        for document in NSDocumentController.shared.documents { document.close() }
        NSApp.terminate(nil)
        return true
    }

    /// The pasteboard automated runs copy to and paste from, instead of the
    /// user's clipboard.
    static let pasteboard = NSPasteboard(name: NSPasteboard.Name("local.macsima.test"))

    /// For UI tests: checks once the launch's documents are open.
    static func startIfUITest() {
        guard isUITest else { return }
        OutputCopy.pasteboard = pasteboard
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            _ = refuseIfForeign(allowed: "/.build/") { FileHandle.standardError.write(Data("TestGuard: \($0)\n".utf8)) }
        }
    }
}
#endif
