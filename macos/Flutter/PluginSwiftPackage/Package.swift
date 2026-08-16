// swift-tools-version: 5.9

// This checked-in aggregate mirrors FlutterGeneratedPluginSwiftPackage, but
// deliberately advertises the app's real deployment target. Flutter regenerates
// its ephemeral aggregate with the SDK default (10.15/12.0), which is too late
// for Xcode's package-resolution step when archiving directly from Xcode.

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .library(
            name: "FlutterGeneratedPluginSwiftPackage",
            type: .static,
            targets: ["FlutterGeneratedPluginSwiftPackage"]
        )
    ],
    dependencies: [
        .package(name: "audioplayers_darwin", path: "../ephemeral/Packages/.packages/audioplayers_darwin-6.5.0"),
        .package(name: "bonsoir_darwin", path: "../ephemeral/Packages/.packages/bonsoir_darwin-7.1.0"),
        .package(name: "connectivity_plus", path: "../ephemeral/Packages/.packages/connectivity_plus-6.1.5"),
        .package(name: "device_info_plus", path: "../ephemeral/Packages/.packages/device_info_plus-12.4.0"),
        .package(name: "erebrus_mlx", path: "../ephemeral/Packages/.packages/erebrus_mlx"),
        .package(name: "erebrus_speech", path: "../ephemeral/Packages/.packages/erebrus_speech"),
        .package(name: "file_picker", path: "../ephemeral/Packages/.packages/file_picker-11.0.2"),
        .package(name: "flutter_secure_storage_darwin", path: "../ephemeral/Packages/.packages/flutter_secure_storage_darwin-0.3.2"),
        .package(name: "google_sign_in_ios", path: "../ephemeral/Packages/.packages/google_sign_in_ios-5.9.0"),
        .package(name: "lib_llama_cpp_macos", path: "../ephemeral/Packages/.packages/lib_llama_cpp_macos"),
        .package(name: "package_info_plus", path: "../ephemeral/Packages/.packages/package_info_plus-8.3.1"),
        .package(name: "record_macos", path: "../ephemeral/Packages/.packages/record_macos-2.1.1"),
        .package(name: "screen_retriever_macos", path: "../ephemeral/Packages/.packages/screen_retriever_macos-0.2.2"),
        .package(name: "share_plus", path: "../ephemeral/Packages/.packages/share_plus-12.0.2"),
        .package(name: "shared_preferences_foundation", path: "../ephemeral/Packages/.packages/shared_preferences_foundation-2.5.6"),
        .package(name: "sqflite_darwin", path: "../ephemeral/Packages/.packages/sqflite_darwin-2.4.3+1"),
        .package(name: "tray_manager", path: "../ephemeral/Packages/.packages/tray_manager-0.5.3"),
        .package(name: "url_launcher_macos", path: "../ephemeral/Packages/.packages/url_launcher_macos-3.2.5"),
        .package(name: "wakelock_plus", path: "../ephemeral/Packages/.packages/wakelock_plus-1.3.3"),
        .package(name: "webview_flutter_wkwebview", path: "../ephemeral/Packages/.packages/webview_flutter_wkwebview-3.26.0"),
        .package(name: "window_manager", path: "../ephemeral/Packages/.packages/window_manager-0.5.2"),
        .package(name: "FlutterFramework", path: "../ephemeral/Packages/.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "audioplayers-darwin", package: "audioplayers_darwin"),
                .product(name: "bonsoir-darwin", package: "bonsoir_darwin"),
                .product(name: "connectivity-plus", package: "connectivity_plus"),
                .product(name: "device-info-plus", package: "device_info_plus"),
                .product(name: "erebrus-mlx", package: "erebrus_mlx"),
                .product(name: "erebrus-speech", package: "erebrus_speech"),
                .product(name: "file-picker", package: "file_picker"),
                .product(name: "flutter-secure-storage-darwin", package: "flutter_secure_storage_darwin"),
                .product(name: "google-sign-in-ios", package: "google_sign_in_ios"),
                .product(name: "lib-llama-cpp-macos", package: "lib_llama_cpp_macos"),
                .product(name: "package-info-plus", package: "package_info_plus"),
                .product(name: "record-macos", package: "record_macos"),
                .product(name: "screen-retriever-macos", package: "screen_retriever_macos"),
                .product(name: "share-plus", package: "share_plus"),
                .product(name: "shared-preferences-foundation", package: "shared_preferences_foundation"),
                .product(name: "sqflite-darwin", package: "sqflite_darwin"),
                .product(name: "tray-manager", package: "tray_manager"),
                .product(name: "url-launcher-macos", package: "url_launcher_macos"),
                .product(name: "wakelock-plus", package: "wakelock_plus"),
                .product(name: "webview-flutter-wkwebview", package: "webview_flutter_wkwebview"),
                .product(name: "window-manager", package: "window_manager"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
