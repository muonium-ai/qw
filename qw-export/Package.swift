// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "qw-export",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "qw-export",
            targets: ["qw-export"]
        )
    ],
    targets: [
        .executableTarget(
            name: "qw-export",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-framework", "AppKit", "-framework", "CoreGraphics"])
            ]
        )
    ]
)
