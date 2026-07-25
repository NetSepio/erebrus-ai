// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "erebrus_mlx",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .library(name: "erebrus-mlx", targets: ["erebrus_mlx"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            exact: "3.31.3"
        ),
        .package(
            url: "https://github.com/huggingface/swift-huggingface",
            from: "0.9.0"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            from: "1.3.0"
        )
    ],
    targets: [
        .target(
            name: "erebrus_mlx",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it collects user
                // data, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
