// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "erebrus_speech",
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "erebrus-speech", targets: ["erebrus_speech"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "erebrus_speech",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
