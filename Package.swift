// swift-tools-version: 6.2
import Foundation
import PackageDescription

private enum PluginToolTarget {
  static let binary = "BylawsPluginTool"
  static let source = "bylaws-cli"
}

private struct PluginToolConfiguration: Decodable {
  enum Mode: String, Decodable {
    case remote
    case source
  }

  let mode: Mode
  let version: String?
  let url: String?
  let checksum: String?
  let sourceRevision: String?
}

private enum PluginToolSelection {
  case localArtifact(path: String)
  case remoteArtifact(url: String, checksum: String)
  case source

  static func load() -> Self {
    if let path = Context.environment["BYLAWS_PLUGIN_ARTIFACT_PATH"] {
      return .localArtifact(path: path)
    }
    if Context.environment["BYLAWS_BUILD_PLUGIN_FROM_SOURCE"] != nil {
      return .source
    }

    #if os(macOS) || (os(Linux) && arch(x86_64))
      let manifestDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
      let configurationURL = manifestDirectory
        .appendingPathComponent("Distribution/PluginTool.json")
      do {
        let data = try Data(contentsOf: configurationURL)
        let configuration = try JSONDecoder().decode(
          PluginToolConfiguration.self,
          from: data
        )
        switch configuration.mode {
        case .source:
          return .source
        case .remote:
          guard let url = configuration.url,
                let checksum = configuration.checksum,
                configuration.version != nil,
                configuration.sourceRevision != nil
          else {
            fatalError("The remote plugin tool configuration is incomplete.")
          }
          return .remoteArtifact(url: url, checksum: checksum)
        }
      } catch {
        fatalError("Cannot read Distribution/PluginTool.json: \(error)")
      }
    #else
      return .source
    #endif
  }

  var dependency: Target.Dependency {
    switch self {
    case .localArtifact, .remoteArtifact:
      .target(name: PluginToolTarget.binary)
    case .source:
      .target(name: PluginToolTarget.source)
    }
  }

  var binaryTarget: Target? {
    switch self {
    case let .localArtifact(path):
      .binaryTarget(name: PluginToolTarget.binary, path: path)
    case let .remoteArtifact(url, checksum):
      .binaryTarget(
        name: PluginToolTarget.binary,
        url: url,
        checksum: checksum
      )
    case .source:
      nil
    }
  }
}

let warningsAsErrorsEnabled =
  Context.environment["BYLAWS_STRICT_BUILD"] != nil

let swiftSettings: [SwiftSetting] =
  [
    .strictMemorySafety(),
    .defaultIsolation(nil),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("ExistentialAny"),
  ] + (warningsAsErrorsEnabled ? [.treatAllWarnings(as: .error)] : [])

private let pluginTool = PluginToolSelection.load()

let package = Package(
  name: "swift-bylaws",
  platforms: [.macOS(.v14), .iOS(.v13)],
  products: [
    .library(name: "Bylaws", targets: ["Bylaws"]),
    .library(name: "BylawsCore", targets: ["BylawsCore"]),
    .library(name: "BylawsSemantics", targets: ["BylawsSemantics"]),
    .library(name: "BylawsIndexStore", targets: ["BylawsIndexStore"]),
    .library(
      name: "BylawsIndex",
      targets: ["BylawsIndex", "BylawsIndexStore"]
    ),
    .library(name: "BylawsInterpreter", targets: ["BylawsInterpreter"]),
    .executable(name: "bylaws", targets: ["bylaws-cli"]),
    .plugin(name: "BylawsPlugin", targets: ["BylawsPlugin"]),
    .plugin(name: "BylawsBuildToolPlugin", targets: ["BylawsBuildToolPlugin"]),
  ],
  traits: [
    .trait(
      name: "CLI",
      description: "Includes the bylaws command-line tool."
    ),
    .trait(
      name: "LanguageServer",
      description: "Includes the Bylaws language server."
    ),
    .default(enabledTraits: ["CLI", "LanguageServer"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-crypto.git",
      exact: "4.5.1"
    ),
    .package(
      url: "https://github.com/apple/swift-system.git",
      exact: "1.7.5"
    ),
    // A range here lets a host project pick the SwiftSyntax major version its
    // own toolchain and macros need.
    .package(
      url: "https://github.com/swiftlang/swift-syntax.git",
      "602.0.0"..<"604.0.0"
    ),
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      exact: "1.8.2"
    ),
    .package(
      url: "https://github.com/swiftlang/swift-tools-protocols.git",
      exact: "0.0.10"
    ),
    .package(
      url: "https://github.com/pointfreeco/swift-clocks.git",
      exact: "1.1.1"
    ),
  ],
  targets: [
    .target(
      name: "BylawsPaths",
      dependencies: [
        .product(name: "SystemPackage", package: "swift-system"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "BylawsSemantics",
      dependencies: [
        "BylawsPaths",
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftOperators", package: "swift-syntax"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "BylawsCore",
      dependencies: [
        "BylawsPaths",
        "BylawsSemantics",
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SystemPackage", package: "swift-system"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "BylawsInterpreter",
      dependencies: [
        "BylawsCore",
        "BylawsPaths",
        "BylawsSemantics",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(
          name: "SwiftParserDiagnostics",
          package: "swift-syntax"
        ),
        .product(name: "SwiftOperators", package: "swift-syntax"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "Bylaws",
      dependencies: ["BylawsCore", "BylawsPaths", "BylawsSemantics"],
      swiftSettings: swiftSettings
    ),
    // Xcode 27 requires this declarations-only target to produce an object.
    .target(name: "CIndexStore"),
    .target(
      name: "BylawsIndexStore",
      dependencies: ["BylawsPaths", "CIndexStore"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "BylawsIndex",
      dependencies: [
        "BylawsIndexStore",
        "BylawsCore",
        "BylawsPaths",
        "BylawsSemantics",
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "BylawsTestSupport",
      dependencies: ["Bylaws", "BylawsPaths"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "BylawsRunner",
      dependencies: [
        "BylawsInterpreter",
        "BylawsCore",
        "BylawsPaths",
        "BylawsSemantics",
        "BylawsIndex",
        "BylawsIndexStore",
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "PortableRuleSupport",
      dependencies: ["Bylaws"],
      path: "Tests/TestModules/PortableRuleSupport",
      swiftSettings: swiftSettings
    ),
    .target(
      name: "PortableRules",
      dependencies: ["Bylaws", "PortableRuleSupport"],
      path: "Tests/TestModules/PortableRules",
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "bylaws-cli",
      dependencies: [
        "BylawsRunner",
        "BylawsInterpreter",
        "BylawsCore",
        "BylawsPaths",
        "BylawsSemantics",
        .product(
          name: "ArgumentParser",
          package: "swift-argument-parser",
          condition: .when(traits: ["CLI"])
        ),
      ],
      swiftSettings: swiftSettings
    ),
    .plugin(
      name: "BylawsPlugin",
      capability: .command(
        intent: .custom(
          verb: "bylaws",
          description: "Checks a package against its architectural rules."
        ),
        permissions: [
          .writeToPackageDirectory(
            reason: "Records baselines beside the package's rules."
          ),
        ]
      ),
      dependencies: [pluginTool.dependency]
    ),
    .plugin(
      name: "BylawsBuildToolPlugin",
      capability: .buildTool(),
      dependencies: [pluginTool.dependency]
    ),
    .testTarget(
      name: "SemanticsTests",
      dependencies: [
        "BylawsSemantics",
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "IndexTests",
      dependencies: [
        "BylawsIndex", "BylawsIndexStore", "BylawsCore", "BylawsPaths",
        "BylawsSemantics", "BylawsTestSupport",
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "InterpreterTests",
      dependencies: [
        "BylawsInterpreter",
        "BylawsCore",
        "BylawsSemantics",
        "BylawsPaths",
        "Bylaws",
        "BylawsTestSupport",
        "PortableRules",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "CLITests",
      dependencies: [
        "bylaws-cli",
        "BylawsRunner",
        "BylawsCore",
        "BylawsPaths",
        "BylawsIndex",
        "BylawsIndexStore",
        "BylawsInterpreter",
        "BylawsSemantics",
        "BylawsTestSupport",
        .product(
          name: "ArgumentParser",
          package: "swift-argument-parser",
          condition: .when(traits: ["CLI"])
        ),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "CoreTests",
      dependencies: [
        "Bylaws",
        "BylawsCore",
        "BylawsInterpreter",
        "BylawsPaths",
        "BylawsSemantics",
        "BylawsTestSupport",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      swiftSettings: swiftSettings
    ),
  ]
)

#if os(macOS) || os(Linux)
  package.products.append(
    .executable(name: "bylaws-lsp", targets: ["bylaws-lsp"])
  )
  package.targets.append(contentsOf: [
    .target(
      name: "BylawsLSP",
      dependencies: [
        "BylawsRunner",
        "BylawsCore",
        "BylawsPaths",
        "BylawsSemantics",
        .product(
          name: "LanguageServerProtocol",
          package: "swift-tools-protocols",
          condition: .when(traits: ["LanguageServer"])
        ),
        .product(
          name: "ToolsProtocolsSwiftExtensions",
          package: "swift-tools-protocols",
          condition: .when(traits: ["LanguageServer"])
        ),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "bylaws-lsp",
      dependencies: [
        "BylawsLSP",
        "BylawsRunner",
        .product(
          name: "LanguageServerProtocol",
          package: "swift-tools-protocols",
          condition: .when(traits: ["LanguageServer"])
        ),
        .product(
          name: "LanguageServerProtocolTransport",
          package: "swift-tools-protocols",
          condition: .when(traits: ["LanguageServer"])
        ),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "LSPTests",
      dependencies: [
        .product(name: "Clocks", package: "swift-clocks"),
        "BylawsCore",
        "BylawsInterpreter",
        "BylawsLSP",
        "BylawsPaths",
        "BylawsRunner",
        "BylawsSemantics",
        "BylawsTestSupport",
        .product(
          name: "LanguageServerProtocol",
          package: "swift-tools-protocols",
          condition: .when(traits: ["LanguageServer"])
        ),
      ],
      swiftSettings: swiftSettings
    ),
  ])
#endif

if let binaryTarget = pluginTool.binaryTarget {
  package.targets.append(binaryTarget)
}

if Context.environment["BYLAWS_BUILD_DOCS"] != nil {
  package.dependencies.append(
    .package(
      url: "https://github.com/swiftlang/swift-docc-plugin",
      exact: "1.5.0"
    )
  )
}
