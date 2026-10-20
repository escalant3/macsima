// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import Foundation
import MaximaKit
import SwiftUI

/// The app's settings (Settings window, Phase 3 step 14), in UserDefaults.
/// Maxima's paths apply when a Maxima starts; abort on error and the plot
/// format reach running sessions at once; fonts and sizes show at once.
enum AppSettings {
    static let maximaPathKey = "MaximaPath"
    static let defaultMaximaPath = "/opt/homebrew/bin/maxima"
    static let gnuplotPathKey = "GnuplotPath"
    static let defaultGnuplotPath = "/opt/homebrew/bin/gnuplot"
    static let abortOnErrorKey = "AbortOnError"
    static let plotFormatKey = "PlotFormat"
    static let codeFontKey = "CodeFont"
    static let codeSizeKey = "CodeSize"
    static let textSizeKey = "TextSize"
    static let mathSizeKey = "MathSize"
    static let defaultZoomKey = "DefaultZoom"

    static let defaultCodeSize = 14.0
    static let defaultTextSize = 14.0
    static let defaultMathSize = 19.0

    /// Where the settings live. Key scripts and UI tests get a store of
    /// their own, emptied at launch: they never change the user's settings,
    /// and the user's settings never change what they test.
    nonisolated(unsafe) static let store: UserDefaults = {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-MacsimaKeyScript") || args.contains("-MacsimaUITest") else { return .standard }
        let suite = "local.macsima.Macsima.tests"
        let store = UserDefaults(suiteName: suite) ?? .standard
        store.removePersistentDomain(forName: suite)
        return store
    }()

    private static var defaults: UserDefaults { store }

    private static func string(_ key: String, _ fallback: String) -> String {
        let stored = defaults.string(forKey: key) ?? ""
        return stored.isEmpty ? fallback : stored
    }

    private static func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return min(max(defaults.double(forKey: key), range.lowerBound), range.upperBound)
    }

    static var maximaPath: String { string(maximaPathKey, defaultMaximaPath) }
    static var gnuplotPath: String { string(gnuplotPathKey, defaultGnuplotPath) }
    /// wxMaxima's "abort on error" (on by default there too).
    static var abortOnError: Bool { defaults.object(forKey: abortOnErrorKey) == nil || defaults.bool(forKey: abortOnErrorKey) }
    /// New plots as SVG (`wxplot_usesvg`) instead of PNG.
    static var plotsAsSVG: Bool { defaults.string(forKey: plotFormatKey) == "svg" }
    /// A font family for code cells; empty for the system's monospaced font.
    static var codeFont: String { defaults.string(forKey: codeFontKey) ?? "" }
    static var codeSize: Double { number(codeSizeKey, defaultCodeSize, 9...36) }
    static var textSize: Double { number(textSizeKey, defaultTextSize, 9...36) }
    static var mathSize: Double { number(mathSizeKey, defaultMathSize, 10...40) }
    /// The zoom new worksheets start with, in percent.
    static var defaultZoom: Int { Int(number(defaultZoomKey, 100, 50...300)) }

    /// The session configuration: paths, abort on error, the plot format,
    /// and pngcairo plots when gnuplot has that terminal (as wxMaxima does).
    static func configuration() async -> MaximaConfiguration {
        var config = MaximaConfiguration()
        config.maximaPath = maximaPath
        config.gnuplotPath = gnuplotPath
        config.abortCellOnError = abortOnError
        if await GnuplotProbe.shared.hasPNGCairo(gnuplot: config.gnuplotPath) {
            config.additionalSetupLines.append(":lisp-quiet (setq $wxplot_pngcairo t)\n")
        }
        if plotsAsSVG { config.additionalSetupLines.append(":lisp-quiet (setq $wxplot_usesvg t)\n") }
        return config
    }

    /// The monospaced families installed, for the code font menu.
    static func monospacedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
    }
}

/// Asks gnuplot once whether it has the pngcairo terminal.
actor GnuplotProbe {
    static let shared = GnuplotProbe()
    private var cached: [String: Bool] = [:]

    func hasPNGCairo(gnuplot: String) -> Bool {
        if let hit = cached[gnuplot] { return hit }
        let p = Process()
        p.executableURL = URL(filePath: gnuplot)
        p.arguments = ["-e", "set terminal"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = FileHandle.nullDevice
        var found = false
        if (try? p.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            found = String(decoding: data, as: UTF8.self).contains("pngcairo")
        }
        cached[gnuplot] = found
        return found
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            MaximaSettings().tabItem { Label("Maxima", systemImage: "function") }
            WorksheetSettings().tabItem { Label("Worksheet", systemImage: "doc.text") }
        }
        .frame(width: 520)
    }
}

private struct MaximaSettings: View {
    @AppStorage(AppSettings.maximaPathKey, store: AppSettings.store) private var maximaPath = ""
    @AppStorage(AppSettings.gnuplotPathKey, store: AppSettings.store) private var gnuplotPath = ""
    @AppStorage(AppSettings.abortOnErrorKey, store: AppSettings.store) private var abortOnError = true
    @AppStorage(AppSettings.plotFormatKey, store: AppSettings.store) private var plotFormat = "png"

    var body: some View {
        Form {
            Section {
                PathField(title: "Maxima", path: $maximaPath, fallback: AppSettings.defaultMaximaPath)
                PathField(title: "gnuplot", path: $gnuplotPath, fallback: AppSettings.defaultGnuplotPath)
            } footer: {
                Text("Used by Maxima sessions started or restarted after the change.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Abort on error", isOn: $abortOnError)
                Text("When a statement fails, the rest of its cell and the cells waiting after it are not run, as in wxMaxima.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Plots", selection: $plotFormat) {
                    Text("PNG").tag("png")
                    Text("SVG").tag("svg")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("These apply to open worksheets at once.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A path to a program, with Choose… and whether it is there.
private struct PathField: View {
    let title: String
    @Binding var path: String
    let fallback: String

    var body: some View {
        let effective = path.isEmpty ? fallback : path
        let ok = FileManager.default.isExecutableFile(atPath: effective)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(title, text: $path, prompt: Text(fallback))
                Button("Choose…") { choose() }
            }
            Label(ok ? "Found" : "Not found or not executable: \(effective)",
                  systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(ok ? Color.secondary : Color.orange)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = URL(filePath: (path.isEmpty ? fallback : path)).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

private struct WorksheetSettings: View {
    @AppStorage(AppSettings.codeFontKey, store: AppSettings.store) private var codeFont = ""
    @AppStorage(AppSettings.codeSizeKey, store: AppSettings.store) private var codeSize = AppSettings.defaultCodeSize
    @AppStorage(AppSettings.textSizeKey, store: AppSettings.store) private var textSize = AppSettings.defaultTextSize
    @AppStorage(AppSettings.mathSizeKey, store: AppSettings.store) private var mathSize = AppSettings.defaultMathSize
    @AppStorage(AppSettings.defaultZoomKey, store: AppSettings.store) private var defaultZoom = 100.0
    @State private var families: [String] = []

    var body: some View {
        Form {
            Section("Fonts") {
                Picker("Code font", selection: $codeFont) {
                    Text("System monospaced").tag("")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Code size: \(Int(codeSize)) pt", value: $codeSize, in: 9...36)
                Stepper("Text size: \(Int(textSize)) pt", value: $textSize, in: 9...36)
                Stepper("Math size: \(Int(mathSize)) px", value: $mathSize, in: 10...40)
                Text("Headings scale with the text size. The worksheet's zoom comes on top.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("New worksheets") {
                Picker("Zoom", selection: $defaultZoom) {
                    ForEach([80.0, 90, 100, 110, 125, 150, 175, 200], id: \.self) { Text("\(Int($0))%").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if families.isEmpty { families = AppSettings.monospacedFamilies() } }
    }
}
