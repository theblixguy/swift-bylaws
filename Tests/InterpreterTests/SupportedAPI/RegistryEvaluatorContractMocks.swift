enum ContractMocks {
  static let semanticSource = """
  import Foundation
  import struct Foundation.URL
  @testable import UIKit

  /// Renders values into text.
  @available(macOS 14, *)
  @MainActor
  public final class Widget<Value: Equatable>: NSObject, Sendable {
    /// Identifies one widget.
    @available(macOS 14, *)
    public typealias Identifier = String

    public final class NestedClass {}
    public actor NestedActor {}
    public struct NestedStruct {}
    public enum NestedEnum { case value }

    public static let shared = Widget<Int>()

    /// The number of rendered values.
    @Published public var count: Int? = 0
    weak var delegate: NSObject?
    lazy var names: [String] = []
    var lookup: [String: Int] = [:]
    var handler: (Int) -> Void = { _ in }

    /// Creates a widget with an optional name.
    @available(macOS 14, *)
    public init?(name: String = "") {
      super.init()
      log(value: name)
    }

    /// Adds a value to the target text.
    @available(macOS 14, *)
    public func render(
      _ value: Value, into target: inout [String]
    ) async throws -> Result<Value, any Error> {
      print(value)
      return .success(value)
    }

    static func make<T: Hashable>(_ seed: T) -> some Sequence<T> { [seed] }
  }

  /// Stores a value between tasks.
  @available(macOS 14, *)
  public actor Store<Value>: Renderable {
    var value: Value

    /// Creates a store with its initial value.
    @available(macOS 14, *)
    init(value: Value) { self.value = value }

    func render() {}
  }

  /// Locates a value on one axis.
  @available(macOS 14, *)
  public struct Point<Value>: Hashable {
    var x: Int

    /// Creates a point at the specified position.
    @available(macOS 14, *)
    init(x: Int) { self.x = x }

    mutating func move() { x += 1 }
  }

  /// Selects a direction for a value.
  @available(macOS 14, *)
  public enum Direction<Value>: Sendable where Value: Sendable {
    case north
    case south

    var label: String { "north" }

    /// Creates the default direction.
    @available(macOS 14, *)
    init() { self = .north }

    func turn() {}
  }

  public enum CompassPoint: String {
    case north = "n"
  }

  public indirect enum Tree {
    /// A node with no child branches.
    case leaf
    case branch(Tree, Tree)
  }

  /// Provides text rendering.
  @available(macOS 14, *)
  public protocol Renderable: AnyObject {
    var title: String { get }
    func render()
  }

  @available(macOS 14, *)
  extension Widget: Renderable {
    public var title: String { "Widget" }
    public func render() {}
  }

  @available(macOS 14, *)
  extension Store: Sendable {}

  @available(macOS 14, *)
  extension Point: Sendable {}

  @available(macOS 14, *)
  extension Direction: Sendable {}

  @available(macOS 14, *)
  extension Renderable: Sendable {}
  """

  static let manifestSource = """
  // swift-tools-version: 6.0
  import PackageDescription

  let previewPort = 8080
  let computedPath = targetPath()
  let computedPackage = packageName()

  let package = Package(
    name: "App",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS("17.0")],
    products: [
      .library(name: "Lib", type: .static, targets: ["Lib"]),
      .executable(name: "tool", targets: ["Tool"]),
    ],
    traits: [
      .default(enabledTraits: ["Fast"]),
      .trait(name: "Fast", description: "Fast mode", enabledTraits: ["Other"]),
      "Other",
    ],
    dependencies: [
      .package(url: "https://example.com/dep.git", exact: "1.2.3-beta.1+build.5"),
      .package(url: "https://example.com/range.git", "1.0.0"..<"2.0.0"),
      .package(url: "https://example.com/closed.git", "1.0.0"..."1.5.0"),
      .package(url: "https://example.com/major.git", from: "2.0.0"),
      .package(url: "https://example.com/minor.git", .upToNextMinor(from: "3.1.0")),
      .package(url: "https://example.com/branch.git", branch: "main"),
      .package(url: "https://example.com/rev.git", revision: "abc123"),
      .package(path: "../Local"),
      .package(
        id: "org.package", from: "1.0.0",
        traits: ["Feature", .trait(name: "Extra", condition: .when(traits: ["Fast"]))]
      ),
    ],
    targets: [
      .target(
        name: "Lib",
        dependencies: [
          .target(name: "Core", condition: .when(platforms: [.macOS])),
          .product(name: "Dep", package: "dep", moduleAliases: ["Dep": "AppDep"]),
          .product(name: "DynamicDep", package: computedPackage),
          "ByName",
        ],
        path: computedPath,
        exclude: ["Legacy"],
        sources: ["A.swift"],
        resources: [
          .process("Assets", localization: .default),
          .copy("Data"),
          .embedInCode("Blob"),
        ],
        publicHeadersPath: "include",
        packageAccess: false,
        cSettings: [.headerSearchPath("include"), .define("C_FLAG", to: "1")],
        swiftSettings: [
          .define("FLAG", .when(configuration: .debug)),
          .unsafeFlags(["-warnings-as-errors"]),
          .enableUpcomingFeature("ExistentialAny"),
          .enableExperimentalFeature("StrictConcurrency"),
          .strictMemorySafety(),
          .interoperabilityMode(.Cxx),
          .swiftLanguageMode(.v6),
          .treatAllWarnings(as: .error),
          .treatWarning("DeprecatedDeclaration", as: .warning),
          .enableWarning("Unused"),
          .disableWarning("Unreachable"),
          .defaultIsolation(MainActor.self),
        ],
        linkerSettings: [.linkedLibrary("z"), .linkedFramework("Foundation")],
        plugins: [.plugin(name: "Gen", package: "tools"), .plugin(name: "Local")]
      ),
      .target(name: "Core"),
      .executableTarget(name: "Tool", dependencies: ["Lib"]),
      .testTarget(name: "LibTests", dependencies: ["Lib"]),
      .macro(name: "Macros"),
      .systemLibrary(
        name: "CLib",
        pkgConfig: "libexample",
        providers: [.brew(["example"]), .apt(["libexample-dev"]), .yum(["ex"]), .nuget(["Ex"])]
      ),
      .binaryTarget(name: "LocalSDK", path: "LocalSDK.xcframework"),
      .binaryTarget(
        name: "RemoteSDK",
        url: "https://example.com/sdk.zip",
        checksum: "abc123"
      ),
      .plugin(name: "Gen", capability: .buildTool()),
      .plugin(
        name: "Cmd",
        capability: .command(
          intent: .custom(verb: "cmd", description: "Runs the command."),
          permissions: [
            .writeToPackageDirectory(reason: "Updates generated files."),
            .allowNetworkConnections(
              scope: .local(ports: [previewPort]),
              reason: "Connects to the preview server."
            ),
            .allowNetworkConnections(
              scope: .all(ports: 8000..<8010),
              reason: "Connects to test services."
            ),
            .allowNetworkConnections(scope: .docker, reason: "Talks to Docker."),
            .allowNetworkConnections(scope: .unixDomainSocket, reason: "Sockets."),
            .allowNetworkConnections(scope: .none, reason: "Nothing."),
          ]
        )
      ),
      .plugin(
        name: "Docs",
        capability: .command(intent: .documentationGeneration(), permissions: [])
      ),
      .plugin(
        name: "Fmt",
        capability: .command(intent: .sourceCodeFormatting(), permissions: [])
      ),
      .target(name: "Dynamic", dependencies: computedDependencies),
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx20
  )
  """

  static let unresolvedManifestSource = """
  // swift-tools-version: 6.0
  import PackageDescription

  let package = Package(name: computedName, targets: [])
  """
}
