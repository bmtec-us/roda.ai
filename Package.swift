// swift-tools-version: 6.0
//
// Package.swift defines ONLY the core library (RodaAiCore) and its unit tests.
// The iOS and macOS app targets, app unit tests, and UI tests live in
// RodaAi.xcodeproj (generated from project.yml via XcodeGen).
//
// Why split: SwiftPM cannot build iOS app bundles. The Xcode project owns
// Sources/RodaAi/, Tests/RodaAiTests/, and Tests/RodaAiUITests/, while
// SPM owns Sources/RodaAiCore/ and Tests/RodaAiCoreTests/.
//
// To regenerate the Xcode project: `xcodegen generate`
// To build core via SPM: `swift build`
// To run core tests via SPM: `swift test`

import PackageDescription

let package = Package(
    name: "RodaAi",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RodaAiCore", targets: ["RodaAiCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", "1.2.0"..<"1.3.0"),
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.3.1"),
        .package(url: "https://github.com/mattt/llama.swift", from: "2.8682.0"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift", from: "0.1.2"),
    ],
    targets: [
        .target(
            name: "RodaAiCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "LlamaSwift", package: "llama.swift"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "Textual", package: "textual"),
            ],
            path: "Sources/RodaAiCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "RodaAiCoreTests",
            dependencies: ["RodaAiCore"],
            path: "Tests/RodaAiCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
