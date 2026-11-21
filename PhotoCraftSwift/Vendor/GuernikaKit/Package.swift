// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GuernikaKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "GuernikaKit", targets: ["GuernikaKit"]),
    ],
    dependencies: [
        .package(path: "../RandomGenerator"),
        .package(path: "../Schedulers"),
    ],
    targets: [
        .target(
            name: "GuernikaKit",
            dependencies: [
                .product(name: "RandomGenerator", package: "RandomGenerator"),
                .product(name: "Schedulers", package: "Schedulers")
            ]
        ),
    ]
)
