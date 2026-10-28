// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import ZIPFoundation

/// Limits for reading a `.wxmx`, which is untrusted input (a zip bomb, or
/// paths that try to escape, must not hurt).
public struct WXMXLimits: Sendable {
    /// Largest `content.xml`, decompressed.
    public var maxContentBytes: UInt64 = 64 << 20
    /// Largest single file in the archive, decompressed.
    public var maxEntryBytes: UInt64 = 128 << 20
    /// Largest sum of all files, decompressed.
    public var maxTotalBytes: UInt64 = 512 << 20
    public var maxEntries = 10_000

    public init() {}
}

public enum WXMXError: Error, Equatable, Sendable, CustomStringConvertible {
    case notAZipArchive
    case missingContent
    case tooManyEntries(Int)
    case entryTooLarge(String)
    case archiveTooLarge
    case unsafePath(String)
    case corrupt(String)
    case badXML(String)
    case notAWorksheet(String)

    public var description: String {
        switch self {
        case .notAZipArchive: String(localized: "The file is not a .wxmx (zip) archive.")
        case .missingContent: String(localized: "The archive has no content.xml.")
        case .tooManyEntries(let n): String(localized: "The archive has \(n) files, more than this app accepts.")
        case .entryTooLarge(let name): String(localized: "\(name) is larger than this app accepts.")
        case .archiveTooLarge: String(localized: "The archive's contents are larger than this app accepts.")
        case .unsafePath(let path): String(localized: "The archive contains an unsafe path: \(path)")
        case .corrupt(let why): String(localized: "The archive is damaged: \(why)")
        case .badXML(let why): String(localized: "content.xml is not valid XML: \(why)")
        case .notAWorksheet(let root): String(localized: "content.xml is not a wxMaxima document (root element \(root)).")
        }
    }
}

/// The files of a `.wxmx`, decompressed under the limits.
struct WXMXFiles {
    var names: [String] = []
    var data: [String: Data] = [:]

    static func read(_ archiveData: Data, limits: WXMXLimits) throws(WXMXError) -> WXMXFiles {
        let archive: Archive
        do { archive = try Archive(data: archiveData, accessMode: .read) } catch { throw .notAZipArchive }
        var files = WXMXFiles()
        var total: UInt64 = 0
        var count = 0
        for entry in archive where entry.type == .file {
            count += 1
            guard count <= limits.maxEntries else { throw .tooManyEntries(count) }
            let path = entry.path
            guard isSafe(path) else { throw .unsafePath(path) }
            let cap = path == "content.xml" ? limits.maxContentBytes : limits.maxEntryBytes
            // The declared size can lie; the consumer counts what really comes out.
            guard entry.uncompressedSize <= cap else { throw .entryTooLarge(path) }
            var bytes = Data()
            do {
                _ = try archive.extract(entry, skipCRC32: false) { chunk in
                    bytes.append(chunk)
                    total += UInt64(chunk.count)
                    if UInt64(bytes.count) > cap { throw WXMXError.entryTooLarge(path) }
                    if total > limits.maxTotalBytes { throw WXMXError.archiveTooLarge }
                }
            } catch let error as WXMXError {
                throw error
            } catch {
                throw .corrupt("\(path): \(error)")
            }
            files.names.append(path)
            files.data[path] = bytes
        }
        return files
    }

    /// Relative, without `..`, not absolute, no backslashes or NULs.
    static func isSafe(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") || path.contains("\0") { return false }
        return !path.split(separator: "/").contains("..")
    }

    /// Writes files into a new archive, uncompressed, in the given order
    /// (wxMaxima: mimetype, format.txt, content.xml, then the images).
    static func write(_ files: [(name: String, data: Data)]) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        let date = Date()
        for (name, data) in files {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count),
                                 modificationDate: date, compressionMethod: .none) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        guard let out = archive.data else { throw WXMXError.corrupt("could not build the archive") }
        return out
    }
}
