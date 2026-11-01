// SPDX-License-Identifier: GPL-2.0-or-later
// Crops a window screenshot for the website: cuts out the empty space between
// the last cell and the status bar, and scales to 1200 px wide.
// Usage: swift scripts/crop-screenshot.swift <in.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: crop-screenshot.swift <in.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: source)
let width = bitmap.pixelsWide, height = bitmap.pixelsHigh

// The background is sampled in the empty space above the status bar.
let probeY = height - 200
let background = bitmap.colorAt(x: width / 2, y: probeY)!
func isBackground(_ y: Int) -> Bool {
    stride(from: 20, to: width - 20, by: 4).allSatisfy { x in
        let c = bitmap.colorAt(x: x, y: y)!
        return abs(c.redComponent - background.redComponent) + abs(c.greenComponent - background.greenComponent)
            + abs(c.blueComponent - background.blueComponent) < 0.03
    }
}
var lastContent = probeY
while lastContent > 0 && isBackground(lastContent) { lastContent -= 1 }
var statusTop = probeY
while statusTop < height - 1 && isBackground(statusTop) { statusTop += 1 }

// The worksheet down to its last cell, a margin, then the status bar.
let margin = 60
let topPart = source.cropping(to: CGRect(x: 0, y: 0, width: width, height: lastContent + margin))!
let statusPart = source.cropping(to: CGRect(x: 0, y: statusTop, width: width, height: height - statusTop))!
let keep = topPart.height + statusPart.height
let outWidth = 1200, outHeight = Int((Double(keep) * Double(outWidth) / Double(width)).rounded())
let context = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high
let scale = Double(outWidth) / Double(width)
let statusHeight = Int((Double(statusPart.height) * scale).rounded())
// Core Graphics draws from the bottom up.
context.draw(statusPart, in: CGRect(x: 0, y: 0, width: outWidth, height: statusHeight))
context.draw(topPart, in: CGRect(x: 0, y: statusHeight, width: outWidth, height: outHeight - statusHeight))
let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: URL(filePath: args[2]))
print("\(args[2]): \(outWidth)x\(outHeight)")
