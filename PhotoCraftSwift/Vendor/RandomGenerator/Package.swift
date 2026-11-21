// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RandomGenerator",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "RandomGenerator",
            targets: ["RandomGenerator"]),
    ],
    targets: [
        .target(
            name: "RandomGenerator",
            dependencies: []),
    ]
)
