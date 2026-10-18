// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-2.0-or-later

import PackageDescription

let package = Package(
    name: "Macsima",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MaximaKit", targets: ["MaximaKit"]),
        .library(name: "WXMLKit", targets: ["WXMLKit"]),
        .library(name: "WorksheetKit", targets: ["WorksheetKit"]),
        .executable(name: "Macsima", targets: ["Macsima"]),
        .executable(name: "maxima-spike", targets: ["maxima-spike"]),
    ],
    targets: [
        .target(name: "MaximaKit"),
        .target(name: "WXMLKit"),
        .target(name: "WorksheetKit"),
        .executableTarget(
            name: "Macsima",
            dependencies: ["MaximaKit", "WXMLKit", "WorksheetKit"],
            path: "App/Macsima"
        ),
        // Phase 0 feasibility spike: raw socket link to Maxima, used to record transcripts.
        .executableTarget(name: "maxima-spike"),
        .testTarget(name: "MaximaKitTests", dependencies: ["MaximaKit"]),
    ],
    swiftLanguageModes: [.v6]
)
