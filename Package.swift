// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-2.0-or-later

import PackageDescription

// With only the Command Line Tools installed (no Xcode), SwiftPM finds neither
// Testing.framework nor lib_TestingInterop.dylib, so `swift test` fails with
// "no such module 'Testing'". These paths fix that and are harmless with Xcode.
let cltDeveloper = "/Library/Developer/CommandLineTools/Library/Developer"
let cltTestingFlags: [String] = [
    "-F", "\(cltDeveloper)/Frameworks",
    "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloper)/Frameworks",
    "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloper)/usr/lib",
]

let package = Package(
    name: "Macsima",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MaximaKit", targets: ["MaximaKit"]),
        .library(name: "WXMLKit", targets: ["WXMLKit"]),
        .library(name: "WorksheetKit", targets: ["WorksheetKit"]),
        .library(name: "MacsimaUI", targets: ["MacsimaUI"]),
        .executable(name: "maxima-spike", targets: ["maxima-spike"]),
        .executable(name: "maxima-session", targets: ["maxima-session"]),
        .executable(name: "macsima-render", targets: ["macsima-render"]),
    ],
    dependencies: [
        // .wxmx files are zip archives. ZIPFoundation is MIT-licensed (GPL-compatible).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19"),
    ],
    targets: [
        .target(
            name: "MaximaKit",
            exclude: ["Resources/README.md"],
            resources: [.copy("Resources/wxMathML.lisp")]
        ),
        .target(name: "WXMLKit"),
        .target(name: "WorksheetKit", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]),
        // Everything the app shows. The app target itself (App/Macsima, built
        // from project.yml with XcodeGen) only holds the @main entry point.
        .target(name: "MacsimaUI", dependencies: ["MaximaKit", "WXMLKit", "WorksheetKit"]),
        // Phase 0 feasibility spike: raw socket link to Maxima, used to record transcripts.
        .executableTarget(name: "maxima-spike"),
        // Phase 1 exit test: runs a session script through MaximaSession.
        .executableTarget(name: "maxima-session", dependencies: ["MaximaKit"]),
        // Phase 2: renders math snapshots and measures the web-view rendering.
        .executableTarget(name: "macsima-render", dependencies: ["MacsimaUI", "WXMLKit", "MaximaKit"]),
        .testTarget(
            name: "MaximaKitTests",
            dependencies: ["MaximaKit"],
            swiftSettings: [.unsafeFlags(["-F", "\(cltDeveloper)/Frameworks"])],
            linkerSettings: [.unsafeFlags(cltTestingFlags)]
        ),
        .testTarget(
            name: "WorksheetKitTests",
            dependencies: ["WorksheetKit", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            swiftSettings: [.unsafeFlags(["-F", "\(cltDeveloper)/Frameworks"])]
        ),
        .testTarget(
            name: "MacsimaUITests",
            dependencies: ["MacsimaUI", "WorksheetKit"],
            swiftSettings: [.unsafeFlags(["-F", "\(cltDeveloper)/Frameworks"])]
        ),
        .testTarget(
            name: "WXMLKitTests",
            dependencies: ["WXMLKit", "MaximaKit"],
            exclude: ["Snapshots"],
            swiftSettings: [.unsafeFlags(["-F", "\(cltDeveloper)/Frameworks"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
