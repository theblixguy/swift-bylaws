// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "CompanyRules",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "CompanyRules", targets: ["CompanyRules"]),
  ],
  dependencies: [
    .package(path: "../../../.."),
  ],
  targets: [
    .target(
      name: "CompanyRules",
      dependencies: [
        .product(name: "Bylaws", package: "swift-bylaws"),
        .product(name: "BylawsIndex", package: "swift-bylaws"),
      ]
    ),
  ]
)
