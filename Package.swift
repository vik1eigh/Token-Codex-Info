// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TokenCodexInfo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenCodexInfo", targets: ["TokenCodexInfo"])
    ],
    targets: [
        .target(
            name: "TokenCodexInfoCore",
            path: "Sources/TokenCodexInfoCore"
        ),
        .executableTarget(
            name: "TokenCodexInfo",
            dependencies: ["TokenCodexInfoCore"],
            path: "Sources/TokenCodexInfo"
        ),
        .testTarget(
            name: "TokenCodexInfoTests",
            dependencies: ["TokenCodexInfoCore"],
            path: "Tests/TokenCodexInfoTests"
        )
    ]
)
