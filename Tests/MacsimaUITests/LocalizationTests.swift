// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing

/// The app's String Catalogs (docs/LOCALIZATION.md): every string is
/// translated into every language the catalog has, with the same
/// placeholders, and every language is declared in project.yml.
struct LocalizationTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let catalogs = ["App/Macsima/Localizable.xcstrings", "App/Macsima/InfoPlist.xcstrings"]

    struct Catalog {
        let source: String
        /// Key → language → every value (each plural form is one).
        var values: [String: [String: [String]]] = [:]
        var languages: Set<String> = []
        /// Keys marked "Don't translate".
        var fixed: Set<String> = []
        /// Keys with a value that isn't marked translated.
        var unfinished: [String] = []

        init(_ path: String) throws {
            let data = try Data(contentsOf: LocalizationTests.root.appending(path: path))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            source = json["sourceLanguage"] as? String ?? "en"
            let strings = json["strings"] as? [String: [String: Any]] ?? [:]
            for (key, entry) in strings {
                if entry["shouldTranslate"] as? Bool == false { fixed.insert(key); continue }
                let localizations = entry["localizations"] as? [String: Any] ?? [:]
                for (language, value) in localizations {
                    languages.insert(language)
                    var units: [[String: Any]] = []
                    Self.collectUnits(value, into: &units)
                    // The sync adds the source language's own entries as "new"; they need nothing.
                    if language != source, units.contains(where: { $0["state"] as? String != "translated" }) {
                        unfinished.append("\(language): \(key)")
                    }
                    values[key, default: [:]][language] = units.compactMap { $0["value"] as? String }
                }
                if values[key] == nil { values[key] = [:] }
            }
            languages.remove(source)
        }

        /// The stringUnits of a localization, through plural and device variations.
        static func collectUnits(_ value: Any, into units: inout [[String: Any]]) {
            guard let dict = value as? [String: Any] else { return }
            if let unit = dict["stringUnit"] as? [String: Any] { units.append(unit) }
            for (key, child) in dict where key != "stringUnit" { collectUnits(child, into: &units) }
        }
    }

    /// `%@`, `%lld`, `%1$@`, ... in order of argument number; `%%` is not one.
    static func placeholders(_ s: String) -> [String] {
        let regex = /%(?:(\d+)\$)?((?:ll|l)?[@dDiuUxXoOfeEgGcCsSp])/
        var next = 0
        return s.matches(of: regex).map { match -> (Int, String) in
            next += 1
            return (match.1.flatMap { Int($0) } ?? next, String(match.2))
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    @Test(arguments: catalogs) func everyStringIsTranslated(_ path: String) throws {
        let catalog = try Catalog(path)
        #expect(catalog.languages.contains("es"), "Spanish is in \(path)")
        #expect(catalog.unfinished.isEmpty, "not marked translated in \(path): \(catalog.unfinished.sorted())")
        for language in catalog.languages.sorted() {
            let missing = catalog.values.filter { $0.value[language] == nil }.keys.sorted()
            #expect(missing.isEmpty, "\(path): no \(language) for \(missing)")
        }
    }

    @Test(arguments: catalogs) func placeholdersMatchTheSource(_ path: String) throws {
        let catalog = try Catalog(path)
        for (key, languages) in catalog.values {
            let expected = Self.placeholders(key)
            for (language, values) in languages {
                for value in values {
                    // A plural form may leave out its number ("one cell").
                    let got = Self.placeholders(value)
                    #expect(got == expected || (values.count > 1 && expected.count == 1 && got.isEmpty),
                            "\(path) \(language): \"\(value)\" has \(got), \"\(key)\" has \(expected)")
                }
            }
        }
    }

    @Test func languagesAreDeclared() throws {
        let yml = try String(contentsOf: Self.root.appending(path: "project.yml"), encoding: .utf8)
        let line = try #require(yml.split(separator: "\n").first { $0.contains("CFBundleLocalizations:") })
        let declared = Set(line.split(separator: "[").last!.dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        for path in Self.catalogs {
            let catalog = try Catalog(path)
            #expect(catalog.languages.union([catalog.source]).isSubset(of: declared),
                    "\(path) has \(catalog.languages.sorted()); project.yml's CFBundleLocalizations has \(declared.sorted())")
        }
    }

    @Test func placeholderParsing() {
        #expect(Self.placeholders("%lld of %lld") == ["lld", "lld"])
        #expect(Self.placeholders("CPU %lld%%") == ["lld"])
        #expect(Self.placeholders("%2$@ en %1$lld") == ["lld", "@"])
    }
}
