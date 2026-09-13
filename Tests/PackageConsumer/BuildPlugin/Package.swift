// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "BuildPluginConsumer",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "../../.."),
    .package(path: "../Plugin/CompanyRules"),
  ],
  targets: [
    .executableTarget(
      name: "App",
      plugins: [
        .plugin(name: "BylawsBuildToolPlugin", package: "swift-bylaws"),
      ]
    ),
    .target(name: "Other"),
    .testTarget(
      name: "ArchitectureTests",
      dependencies: [
        .product(name: "Bylaws", package: "swift-bylaws"),
        .product(name: "CompanyRules", package: "CompanyRules"),
      ],
      path: "Rules"
    ),
  ]
)
