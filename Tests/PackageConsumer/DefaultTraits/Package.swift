// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "DefaultTraitsConsumer",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "Consumer", targets: ["Consumer"]),
  ],
  dependencies: [
    .package(path: "../../.."),
  ],
  targets: [
    .target(
      name: "Consumer",
      dependencies: [
        .product(name: "Bylaws", package: "swift-bylaws"),
      ]
    ),
  ]
)
