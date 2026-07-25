# Erebrus MLX

Private Flutter plugin providing an MLX Swift LM 3.31.3 bridge for Erebrus AI.
It supports capability probing, local MLX package loading, streaming text,
cancellation, and explicit unload on iOS 17+ and macOS 14+.

The app must enable Flutter Swift Package Manager integration. The native
package pins `mlx-swift-lm` to 3.31.3 and resolves its MLX Swift dependency
through SwiftPM.

## Build prerequisites

- Xcode with the matching Metal Toolchain installed
- iOS 17+ or macOS 14+
- Swift package and macro fingerprint validation enabled interactively, or
  `-skipPackagePluginValidation -skipMacroValidation` in non-interactive CI

This bridge deliberately accepts local model directories. Catalog/download
code is responsible for fetching every required MLX package file and verifying
its revision and digest before calling `loadModel`.
