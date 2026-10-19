// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import SwiftUI

/// An animation (`with_slider`, `wxanimate`): one frame at a time, with
/// play and pause, a slider to pick the frame, and the frame number. Plays at
/// the `slide` element's frame rate (`fr`, frames per second; 2 if absent,
/// as wxMaxima), from the frame it names, and starts playing when it says
/// `running="true"`.
struct AnimationOutputView: View {
    let frames: [Data]
    var format = "png"
    let label: String?
    let attributes: [String: String]

    @State private var images: [NSImage] = []
    @State private var index = 0
    @State private var playing = false
    @Environment(\.worksheetScale) private var scale

    private var frameRate: Double {
        attributes["fr"].flatMap(Double.init).map { max(0.1, min($0, 60)) } ?? 2
    }

    var body: some View {
        let metrics = WorksheetMetrics(scale: scale)
        VStack(alignment: .leading, spacing: 4 * scale) {
            if images.indices.contains(index) {
                ImageOutputView(image: images[index], label: label)
            } else {
                Color.clear.frame(height: 40)
            }
            HStack(spacing: 8) {
                Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") {
                    playing.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("animation-play")
                if images.count > 1 {
                    Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                           in: 0...Double(images.count - 1), step: 1)
                        .frame(maxWidth: min(images.first?.size.width ?? 400, 640) * scale - 90)
                        .accessibilityIdentifier("animation-slider")
                }
                Text("\(index + 1) / \(max(images.count, 1))")
                    .font(.system(size: metrics.gutterFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("animation-frame")
            }
            .padding(.leading, metrics.gutterWidth + metrics.mathGap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            images = frames.compactMap { ImageDecoding.image($0, format: format) }
            index = min(Int(attributes["frame"] ?? "") ?? 0, max(images.count - 1, 0))
            playing = attributes["running"] == "true"
        }
        .task(id: playing) {
            while playing, images.count > 1 {
                try? await Task.sleep(for: .seconds(1 / frameRate))
                if Task.isCancelled { return }
                index = (index + 1) % images.count
            }
        }
    }
}
