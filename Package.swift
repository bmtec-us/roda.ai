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
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.31.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.1.0"),
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
    ]
)
