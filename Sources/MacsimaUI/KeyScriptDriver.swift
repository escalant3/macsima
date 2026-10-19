// SPDX-License-Identifier: GPL-2.0-or-later

#if DEBUG
import AppKit
import SwiftUI
import WorksheetKit

/// Drives the app from a script of key events, for checking the editor
/// without Accessibility permission: synthesized NSEvents are posted to the
/// app's own event queue, the same path as typing (text views, onKeyPress,
/// menu key equivalents, undo grouping). Launch with `-MacsimaKeyScript <file>`. Debug builds only.
///
/// Lines: `type <text>`, `key <name> [cmd] [shift] [option]` (names: return,
/// delete, escape, tab, up, down, or one character), `menu <item title>`,
/// `wait <seconds>`, `dump <path>` (cells as JSON), `shot <path>` (the key
/// window), `undo-state <tag>` (logs what Cmd+Z would do), `quit`
/// (discarding changes). `#` starts a comment. It refuses to run when a
/// document outside `.build/keyscripts` is open (a restored window, say).
@MainActor
enum KeyScriptDriver {
    private static var started = false

    static func startIfRequested() {
        guard !started else { return }
        started = true
        guard let path = UserDefaults.standard.string(forKey: "MacsimaKeyScript"),
              let script = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            // Never type into the user's own documents (a restored window, say):
            // only untitled worksheets and files under .build/keyscripts.
            if TestGuard.refuseIfForeign(allowed: "/.build/keyscripts/", log: log) { return }
            NSApp.activate()
            documentWindow?.makeKeyAndOrderFront(nil)
            log("app active: \(NSApp.isActive), key window: \(NSApp.keyWindow != nil)")
            for raw in script.split(separator: "\n").map(String.init) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                await run(line)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    static func run(_ line: String) async {
        let (word, rest) = split(line)
        switch word {
        case "type":
            // Paced like typing, so SwiftUI can push each edit through the binding.
            for ch in rest {
                send(String(ch), keyCode: 0, flags: [])
                try? await Task.sleep(for: .milliseconds(25))
            }
        case "key":
            let parts = rest.split(separator: " ").map(String.init)
            guard let name = parts.first else { return }
            var flags: NSEvent.ModifierFlags = []
            if parts.contains("cmd") { flags.insert(.command) }
            if parts.contains("shift") { flags.insert(.shift) }
            if parts.contains("option") { flags.insert(.option) }
            let (chars, code) = keys[name] ?? (name, keyCodes[name] ?? 0)
            if !flags.intersection([.command, .control]).isEmpty {
                refreshMenus(NSApp.mainMenu)
                try? await Task.sleep(for: .milliseconds(100))
            }
            send(chars, keyCode: code, flags: flags)
        case "menu":
            refreshMenus(NSApp.mainMenu)
            try? await Task.sleep(for: .milliseconds(100))
            if let item = findMenuItem(rest, in: NSApp.mainMenu), let menu = item.menu {
                menu.performActionForItem(at: menu.index(of: item))
            } else {
                log("no menu item \(rest)")
            }
        case "wait":
            try? await Task.sleep(for: .milliseconds(Int((Double(rest) ?? 1) * 1000)))
        case "dump":
            dump(to: rest)
        case "shot":
            if let window = documentWindow {
                let p = Process()
                p.executableURL = URL(filePath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", String(window.windowNumber), rest]
                try? p.run()
                p.waitUntilExit()
            }
        case "undo-state":
            // Debugging aid: what Cmd+Z would do right now.
            let undo = NSApp.keyWindow?.undoManager
            log("undo-state \(rest): level \(undo?.groupingLevel ?? -1), canUndo \(undo?.canUndo ?? false), action \"\(undo?.undoActionName ?? "")\", groupsByEvent \(undo?.groupsByEvent ?? false), same as controller's \(undo === WorksheetController.keyController?.undoManager)")
        case "quit":
            // Discard changes, so no "save changes?" sheet stops the quit.
            NSDocumentController.shared.documents.forEach { $0.updateChangeCount(.changeCleared) }
            // From the run loop, as a real quit arrives: terminating inside this
            // main-actor task would block the delegate's shutdown task.
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        default:
            log("unknown line: \(line)")
        }
    }

    private static let keys: [String: (String, UInt16)] = [
        "return": ("\r", 36), "delete": ("\u{7F}", 51), "backspace": ("\u{8}", 51), "escape": ("\u{1B}", 53), "tab": ("\t", 48),
        "up": (String(UnicodeScalar(NSUpArrowFunctionKey)!), 126),
        "down": (String(UnicodeScalar(NSDownArrowFunctionKey)!), 125),
    ]
    private static let keyCodes: [String: UInt16] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "r": 15, "z": 6, ".": 47, "n": 45, "s": 1,
    ]

    /// The key window, or else the frontmost document window (the app may
    /// not be active when launched from a terminal).
    static var documentWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible && $0.canBecomeKey }
    }

    /// Delivers like NSApplication.sendEvent does for an active app: menu key
    /// equivalents first, then the window's first responder.
    private static func send(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let window = documentWindow else { log("no window"); return }
        let ignoring = flags.contains(.shift) ? characters.lowercased() : characters
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: keyCode) else { continue }
            if NSApp.isActive {
                // Through the app's event queue, so every event completes a real
                // event-loop cycle (AppKit closes undo groups at the end of one;
                // calling sendEvent directly left typing groups open).
                NSApp.postEvent(event, atStart: false)
            } else if type == .keyDown, !flags.intersection([.command, .control]).isEmpty,
                      NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                continue
            } else {
                window.sendEvent(event)
            }
        }
    }

    /// What AppKit does before showing a menu or matching a key equivalent:
    /// lets each menu's delegate (SwiftUI) rebuild its items, then validates.
    private static func refreshMenus(_ menu: NSMenu?) {
        guard let menu else { return }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        for item in menu.items { refreshMenus(item.submenu) }
    }

    private static func findMenuItem(_ title: String, in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.title == title { return item }
            if let found = findMenuItem(title, in: item.submenu) { return found }
        }
        return nil
    }

    private static func dump(to path: String) {
        guard let controller = WorksheetController.keyController else { log("no controller"); return }
        let cells = controller.document.worksheet.cells.map { cell -> [String: Any] in
            ["kind": cell.kind.rawValue, "input": cell.input, "outputs": cell.outputs.map(describe),
             "label": cell.inputLabel ?? -1, "focused": cell.id == controller.focusedCell]
        }
        let info: [String: Any] = ["cells": cells, "state": controller.sessionState.rawValue,
                                   "status": controller.statusMessage ?? "", "running": controller.running.count]
        let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: URL(filePath: path))
    }

    /// A short description of an output for dumps: kind, then the gist.
    private static func describe(_ output: Output) -> String {
        switch output {
        case .math(let xml):
            let out = TranslationCache.shared.translate(xml)
            return "math \(out.label ?? "-") \(out.plainText)"
        case .text(let t): return "text \(t)"
        case .error(let kind, let message): return "error \(kind ?? "-") \(message)"
        case .image(let data, let format, let label, _): return "image \(label ?? "-") \(format) \(data.count) bytes"
        case .question(let prompt, let answer):
            return "question \(TranslationCache.shared.translate(prompt).plainText) answer=\(answer ?? "nil")"
        }
    }

    private static func split(_ line: String) -> (String, String) {
        guard let space = line.firstIndex(of: " ") else { return (line, "") }
        return (String(line[..<space]), String(line[line.index(after: space)...]))
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("KeyScriptDriver: \(message)\n".utf8))
    }
}
#endif
