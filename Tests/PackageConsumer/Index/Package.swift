// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "IndexConsumer",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "Consumer", targets: ["Consumer"]),
  ],
  dependencies: [
    .package(path: "../../..", traits: []),
  ],
  targets: [
    .target(
      name: "Consumer",
      dependencies: [
        .product(name: "BylawsIndex", package: "swift-bylaws"),
      ]
    ),
  ]
)
