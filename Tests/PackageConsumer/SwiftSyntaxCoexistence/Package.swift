// swift-tools-version: 6.2
import PackageDescription

guard let swiftSyntaxVersion = Context.environment["SWIFT_SYNTAX_VERSION"],
      let swiftSyntaxVersion = Version(swiftSyntaxVersion)
else {
  fatalError("Set SWIFT_SYNTAX_VERSION to the artifact's SwiftSyntax version.")
}

let package = Package(
  name: "SwiftSyntaxCoexistence",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "../../..", traits: []),
    .package(
      url: "https://github.com/swiftlang/swift-syntax.git",
      exact: swiftSyntaxVersion
    ),
  ],
  targets: [
    .executableTarget(
      name: "SwiftSyntaxCoexistence",
      dependencies: [
        .product(name: "Bylaws", package: "swift-bylaws"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    ),
  ]
)
