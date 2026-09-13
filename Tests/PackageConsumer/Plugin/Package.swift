// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "PluginConsumer",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "../../.."),
    .package(path: "CompanyRules"),
  ],
  targets: [
    .executableTarget(
      name: "App",
      dependencies: [
        .product(name: "CompanyRules", package: "CompanyRules"),
      ]
    ),
  ]
)
