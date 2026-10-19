// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WorksheetKit
@testable import MacsimaUI

struct ImageDecodingTests {
    /// The "Scalable ginger horses" image cell in wxMaxima's testbench is an .svgz.
    @Test func svgzFromWxMaxima() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/wxmx/wxmaxima-samples/testbench_simple.wxmx")
        let r = try WXMXReader.read(try Data(contentsOf: url))
        let svgz = r.worksheet.cells.compactMap { cell -> Data? in
            if cell.kind == .image, case .image(let data, "svgz", _, _)? = cell.outputs.first { data } else { nil }
        }
        #expect(svgz.count == 1)
        let svg = try #require(ImageDecoding.gunzip(svgz[0]))
        #expect(String(decoding: svg.prefix(400), as: UTF8.self).contains("<svg"))
        let image = try #require(ImageDecoding.image(svgz[0], format: "svgz"))
        #expect(image.size.width > 10 && image.size.height > 10)
    }
}
