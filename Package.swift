// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VideoHash",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "VideoHash",
            targets: ["VideoHash"]
        ),
        .executable(
            name: "test-hash",
            targets: ["TestHash"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.7.0")
    ],
    targets: [
        .target(
            name: "VideoHash",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "TestHash",
            dependencies: ["VideoHash"],
            path: "Sources/TestHash"
        ),
        .testTarget(
            name: "VideoHashTests",
            dependencies: ["VideoHash"]
        )
    ]
)
