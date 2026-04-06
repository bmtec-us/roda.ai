// swift-tools-version: 6.0

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
    ],
    targets: [
        .executableTarget(
            name: "RodaAi",
            dependencies: [
                "RodaAiCore",
                .product(name: "Textual", package: "textual"),
            ],
            path: "Sources/RodaAi"
        ),
        .target(
            name: "RodaAiCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/RodaAiCore"
        ),
        .testTarget(
            name: "RodaAiCoreTests",
            dependencies: ["RodaAiCore"],
            path: "Tests/RodaAiCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "RodaAiTests",
            dependencies: ["RodaAi", "RodaAiCore"],
            path: "Tests/RodaAiTests"
        ),
        // NOTE: XCUITest-style UI tests require a real Xcode project with a
        // UI Testing bundle. SwiftPM only supports unit test bundles, so the
        // tests in Tests/RodaAiUITests/ that use XCUIApplication will not run
        // via `swift test`. They will run when this package is opened in Xcode
        // and a UI Testing target is added there. For now, we add the target
        // so the files compile and lint, but actual UI test execution requires
        // an Xcode project wrapper (planned for Phase 10 launch prep).
        .testTarget(
            name: "RodaAiUITests",
            dependencies: ["RodaAi", "RodaAiCore"],
            path: "Tests/RodaAiUITests"
        ),
    ]
)
