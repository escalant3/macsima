// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import MaximaKit
import SwiftUI

/// The one setting Phase 2 has: where Maxima is.
enum AppSettings {
    static let maximaPathKey = "MaximaPath"
    static let defaultMaximaPath = "/opt/homebrew/bin/maxima"

    static var maximaPath: String {
        let stored = UserDefaults.standard.string(forKey: maximaPathKey) ?? ""
        return stored.isEmpty ? defaultMaximaPath : stored
    }

    /// The session configuration: the Maxima path, and pngcairo plots when
    /// gnuplot has that terminal (as wxMaxima does).
    static func configuration() async -> MaximaConfiguration {
        var config = MaximaConfiguration()
        config.maximaPath = maximaPath
        if await GnuplotProbe.shared.hasPNGCairo(gnuplot: config.gnuplotPath) {
            config.additionalSetupLines = [":lisp-quiet (setq $wxplot_pngcairo t)\n"]
        }
        return config
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
    @AppStorage(AppSettings.maximaPathKey) private var maximaPath = ""

    var body: some View {
        Form {
            TextField("Maxima", text: $maximaPath, prompt: Text(AppSettings.defaultMaximaPath))
            Text("Used by windows opened or restarted after the change.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
