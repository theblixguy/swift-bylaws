// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftSyntaxArtifact",
  platforms: [.macOS(.v14)],
  products: [
    .executable(
      name: "swift-syntax-artifact",
      targets: ["SwiftSyntaxArtifact"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      exact: "1.8.2"
    ),
  ],
  targets: [
    .target(name: "SwiftSyntaxArtifactCore"),
    .executableTarget(
      name: "SwiftSyntaxArtifact",
      dependencies: [
        "SwiftSyntaxArtifactCore",
        .product(
          name: "ArgumentParser",
          package: "swift-argument-parser"
        ),
      ]
    ),
    .testTarget(
      name: "SwiftSyntaxArtifactCoreTests",
      dependencies: ["SwiftSyntaxArtifactCore"]
    ),
  ]
)
