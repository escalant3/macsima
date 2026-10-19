// SPDX-License-Identifier: GPL-2.0-or-later

#if DEBUG
import AppKit
import SwiftUI
import WorksheetKit

/// Drives the app from a script of key events, for checking the editor
/// without Accessibility permission: synthesized NSEvents are posted to the
/// app's own event queue, the same path as typing (text views, onKeyPress,
/// menu key equivalents, undo grouping). `key` events with a key code are
/// made from CGEvents, as the keyboard makes them; XCUITest (Tests/UITests)
/// covers real keystrokes. Launch with `-MacsimaKeyScript <file>`. Debug builds only.
///
/// Lines: `type <text>`, `key <name> [cmd] [shift] [option]` (names: return,
/// delete, escape, tab, up, down, left, right, or one character), `menu <item title>`,
/// `wait <seconds>`, `appearance dark|light|system`, `sheet <button>`, `procs <path>`, `find-replacement <text>`, `find-replace-all`, `resize <width> <height>`, `dump <path>` (cells as JSON), `shot <path>` (the key
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
            // Synthesized keys only reach an active app: say when another app
            // takes over (someone using the Mac while a script runs).
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                   object: nil, queue: .main) { _ in
                let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                FileHandle.standardError.write(Data("KeyScriptDriver: app lost focus to \(front)\n".utf8))
            }
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
                send(String(ch), ignoring: String(ch), keyCode: 0, flags: [])
                try? await Task.sleep(for: .milliseconds(25))
            }
        case "key":
            let parts = rest.split(separator: " ").map(String.init)
            guard let name = parts.first else { return }
            var flags: NSEvent.ModifierFlags = []
            if parts.contains("cmd") { flags.insert(.command) }
            if parts.contains("shift") { flags.insert(.shift) }
            if parts.contains("option") { flags.insert(.option) }
            var (chars, code) = keys[name] ?? (name, keyCodes[name] ?? 0)
            var ignoring = chars
            // As a keyboard sends a shifted letter (seen with XCUITest's real
            // Cmd+Shift+G): charactersIgnoringModifiers keeps Shift ("G"),
            // while characters is lowercase when Command is down.
            if flags.contains(.shift), name.count == 1 {
                ignoring = chars.uppercased()
                chars = flags.contains(.command) ? chars.lowercased() : chars.uppercased()
            }
            if !flags.intersection([.command, .control]).isEmpty {
                refreshMenus(NSApp.mainMenu)
                try? await Task.sleep(for: .milliseconds(100))
            }
            send(chars, ignoring: ignoring, keyCode: code, flags: flags)
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
        case "responder":
            // Debugging aid: who has the keyboard focus.
            let responder = NSApp.keyWindow?.firstResponder
            let text = (responder as? NSTextView)?.string ?? ""
            log("responder \(rest): \(responder.map { String(describing: type(of: $0)) } ?? "nil") \(text.prefix(20).debugDescription)")
        case "menu-info":
            // Debugging aid: a menu item's key equivalent.
            refreshMenus(NSApp.mainMenu)
            if let item = findMenuItem(rest, in: NSApp.mainMenu) {
                log("menu-info \(rest): \(item.keyEquivalent.debugDescription) mask \(item.keyEquivalentModifierMask.rawValue) enabled \(item.isEnabled)")
            }
        case "sheet":
            // Presses a button of the sheet on the document window (the
            // save sheet when closing an edited worksheet).
            guard let sheet = NSApp.orderedWindows.compactMap(\.attachedSheet).first ?? NSApp.keyWindow?.attachedSheet else {
                log("no sheet"); return
            }
            let buttons = allButtons(in: sheet.contentView)
            if let button = buttons.first(where: { $0.title == rest }) {
                button.performClick(nil)
            } else {
                log("no button \(rest) in the sheet: \(buttons.map(\.title))")
            }
        case "procs":
            // The app's child processes (one Maxima per window), one per line.
            let p = Process()
            p.executableURL = URL(filePath: "/bin/ps")
            p.arguments = ["-A", "-o", "ppid=,pid=,command="]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let own = String(getpid())
            let lines = String(decoding: output, as: UTF8.self).split(separator: "\n").filter {
                $0.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) == own
                    && !$0.contains("/bin/ps")
            }
            try? lines.joined(separator: "\n").write(toFile: rest, atomically: true, encoding: .utf8)
        case "appearance":
            // dark, light, or system (the user's setting).
            NSApp.appearance = rest == "dark" ? NSAppearance(named: .darkAqua)
                : rest == "light" ? NSAppearance(named: .aqua) : nil
        case "find-replacement":
            // The replacement field's text (typing goes to the query field).
            WorksheetController.keyController?.find.replacement = rest
        case "find-replace-all":
            WorksheetController.keyController?.find.replaceAll()
        case "resize":
            // The key window's content size in points: `resize <width> <height>`.
            let size = rest.split(separator: " ").compactMap { Double($0) }
            if size.count == 2, let window = documentWindow {
                window.setContentSize(CGSize(width: size[0], height: size[1]))
            }
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
        "left": (String(UnicodeScalar(NSLeftArrowFunctionKey)!), 123),
        "right": (String(UnicodeScalar(NSRightArrowFunctionKey)!), 124),
    ]
    private static let keyCodes: [String: UInt16] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "r": 15, "z": 6, ".": 47, "n": 45, "s": 1, "f": 3, "g": 5, "e": 14, "/": 44, "=": 24, "-": 27, "w": 13,
    ]

    /// The key window, or else the frontmost document window (the app may
    /// not be active when launched from a terminal).
    static var documentWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible && $0.canBecomeKey }
    }

    /// Delivers like NSApplication.sendEvent does for an active app: menu key
    /// equivalents first, then the window's first responder.
    private static func send(_ characters: String, ignoring: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let window = documentWindow else { log("no window"); return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = keyCode != 0 && keyCode != 51
                    ? hardwareLikeEvent(keyCode: keyCode, down: type == .keyDown, flags: flags)
                    : NSEvent.keyEvent(
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

    /// A key event made from a CGEvent, as the keyboard makes them: AppKit
    /// translates the key code through the keyboard layout, which menu
    /// matching needs for shifted keys (Cmd+Shift+G matched nothing when the
    /// event was made from characters alone).
    private static func hardwareLikeEvent(keyCode: UInt16, down: Bool, flags: NSEvent.ModifierFlags) -> NSEvent? {
        guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return nil }
        var cgFlags: CGEventFlags = []
        if flags.contains(.command) { cgFlags.insert(.maskCommand) }
        if flags.contains(.shift) { cgFlags.insert(.maskShift) }
        if flags.contains(.option) { cgFlags.insert(.maskAlternate) }
        if flags.contains(.control) { cgFlags.insert(.maskControl) }
        cg.flags = cgFlags
        return NSEvent(cgEvent: cg)
    }

    /// What AppKit does before showing a menu or matching a key equivalent:
    /// lets each menu's delegate (SwiftUI) rebuild its items, then validates.
    private static func refreshMenus(_ menu: NSMenu?) {
        guard let menu else { return }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        for item in menu.items { refreshMenus(item.submenu) }
    }

    private static func allButtons(in view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap { allButtons(in: $0) }
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
             "label": cell.inputLabel ?? -1, "focused": cell.id == controller.focusedCell,
             "editorText": controller.existingEditor(for: cell.id)?.string ?? NSNull(),
             "inWindow": controller.existingEditor(for: cell.id)?.window != nil,
             "backgrounds": controller.existingEditor(for: cell.id).map { describe($0)["backgrounds"] ?? [] } ?? [],
             "errorMarks": controller.errorMarks[cell.id].map { marks -> [String: Any] in
                 ["statements": marks.statements.map { [$0.location, $0.length] },
                  "spots": marks.spots.map { [$0.location, $0.length] }, "current": marks.text == cell.input]
             } ?? NSNull()]
        }
        var info: [String: Any] = ["cells": cells, "state": controller.sessionState.rawValue,
                                   "status": controller.statusMessage ?? "", "running": controller.running.count]
        info["zoom"] = controller.document.worksheet.zoom
        info["renders"] = MathSnapshotRenderer.shared.recent.map { r -> [String: Any] in
            ["label": r.label ?? "", "wrap": r.wrap.map { Int($0) } ?? -1,
             "width": Int(r.size.width), "height": Int(r.size.height)]
        }
        info["windowWidth"] = Int(documentWindow?.contentLayoutRect.width ?? 0)
        let find = controller.find
        info["find"] = ["visible": find.isVisible, "query": find.query, "status": find.status,
                        "current": find.current ?? -1, "count": find.matches.count] as [String: Any]
        if let current = find.current, current < find.matches.count,
           let editor = controller.existingEditor(for: find.matches[current].cell) {
            info["findSelection"] = [editor.selectedRange().location, editor.selectedRange().length]
        }
        if let editor = NSApp.keyWindow?.firstResponder as? CellTextView {
            info["editor"] = describe(editor)
        }
        let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: URL(filePath: path))
    }

    /// The focused editor: its selection and its coloured ranges as
    /// `text=colorName` (rendering attributes, which the model doesn't hold).
    private static func describe(_ editor: CellTextView) -> [String: Any] {
        var colors: [String] = [], backgrounds: [String] = []
        if let layout = editor.textLayoutManager, let content = layout.textContentManager {
            let ns = editor.string as NSString
            layout.enumerateRenderingAttributes(from: layout.documentRange.location, reverse: false) { _, attributes, range in
                let from = content.offset(from: layout.documentRange.location, to: range.location)
                let length = content.offset(from: range.location, to: range.endLocation)
                let text = ns.substring(with: NSRange(location: from, length: length))
                if let color = attributes[.foregroundColor] as? NSColor {
                    colors.append("\(text)=\(name(color))")
                }
                if let color = attributes[.backgroundColor] as? NSColor {
                    backgrounds.append("\(from):\(text)=\(name(color))")
                }
                return true
            }
        }
        let selection = editor.selectedRange()
        return ["colors": colors, "backgrounds": backgrounds, "selection": [selection.location, selection.length]]
    }

    private static func name(_ color: NSColor) -> String {
        color.type == .catalog ? color.colorNameComponent : (color.type == .componentBased ? "\(color)" : "dynamic")
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
