// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Photato",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Photato", targets: ["PhotoCraft"]),
    .library(name: "PhotoCraftCore", targets: ["PhotoCraftCore"]),
  ],
  dependencies: [.package(path: "Vendor/GuernikaKit")],
  targets: [
    .target(name: "PhotoCraftCore"),
    .target(
      name: "PhotoCraftImaging",
      dependencies: ["PhotoCraftCore", .product(name: "GuernikaKit", package: "GuernikaKit")],
      resources: [.copy("Resources/FactoryRGB8Gray20.zlib")]),
    .target(name: "PhotoCraftAI"),
    .executableTarget(
      name: "PhotoCraft", dependencies: ["PhotoCraftCore", "PhotoCraftImaging", "PhotoCraftAI"]),
    .testTarget(
      name: "PhotoCraftCoreTests", dependencies: ["PhotoCraftCore"], resources: [.copy("Fixtures")]),
    .testTarget(
      name: "PhotoCraftImagingTests", dependencies: ["PhotoCraftImaging", "PhotoCraftCore"],
      resources: [.copy("Fixtures")]),
    .testTarget(name: "PhotoCraftAITests", dependencies: ["PhotoCraftAI"]),
    .testTarget(
      name: "PhotoCraftAppTests",
      dependencies: ["PhotoCraft", "PhotoCraftCore", "PhotoCraftImaging"],
      resources: [.copy("Fixtures")]),
  ]
)
