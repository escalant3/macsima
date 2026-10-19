// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import Foundation

/// Images from outputs and image cells: what NSImage reads (PNG, JPEG, GIF,
/// SVG), plus `.svgz`, gzip-compressed SVG, which wxMaxima also stores.
enum ImageDecoding {
    static func image(_ data: Data, format: String) -> NSImage? {
        if format.lowercased() == "svgz" { return gunzip(data).flatMap(NSImage.init(data:)) }
        return NSImage(data: data)
    }

    /// The content of a gzip file (RFC 1952): the header, then raw DEFLATE,
    /// which NSData's zlib algorithm reads.
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var i = 10
        if flags & 0x04 != 0 {   // FEXTRA
            guard i + 2 <= bytes.count else { return nil }
            i += 2 + Int(bytes[i]) + Int(bytes[i + 1]) << 8
        }
        if flags & 0x08 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 }   // FNAME
        if flags & 0x10 != 0 { while i < bytes.count, bytes[i] != 0 { i += 1 }; i += 1 }   // FCOMMENT
        if flags & 0x02 != 0 { i += 2 }   // FHCRC
        guard i < bytes.count - 8 else { return nil }
        let deflated = Data(bytes[i..<(bytes.count - 8)])
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }
}
