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
    if Context.environment["BYLAWS_BUILD_PLUGIN_FROM_SOURCE"] != nil
      || Context.environment["SPI_PROCESSING"] == "1"
    {
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

private enum SwiftSyntaxArtifact {
  static let sourcePackage = "https://github.com/swiftlang/swift-syntax.git"
  static let minimumSourceVersion = Version(602, 0, 0)
  static let releaseRoot =
    "https://github.com/theblixguy/swift-bylaws/releases/download"

  static var compiler: Compiler {
    #if compiler(>=6.5) && compiler(<6.6)
      Compiler(series: "6.5", configuration: "605")
    #elseif compiler(>=6.4.1) && compiler(<6.5)
      Compiler(series: "6.4", configuration: "604")
    #elseif compiler(>=6.4) && compiler(<6.5)
      Compiler(
        series: "6.4",
        configuration: "604",
        artifactCompilerVersion: "6.4"
      )
    #elseif compiler(>=6.3.4) && compiler(<6.4)
      Compiler(series: "6.3", configuration: "603")
    #elseif compiler(>=6.3.3) && compiler(<6.4)
      Compiler(
        series: "6.3",
        configuration: "603",
        artifactCompilerVersion: "6.3.3"
      )
    #elseif compiler(>=6.3) && compiler(<6.4)
      Compiler(series: "6.3", configuration: "603")
    #elseif compiler(>=6.2.4) && compiler(<6.3)
      Compiler(series: "6.2", configuration: "602")
    #elseif compiler(>=6.2.3) && compiler(<6.3)
      Compiler(
        series: "6.2",
        configuration: "602",
        artifactCompilerVersion: "6.2.3"
      )
    #elseif compiler(>=6.2) && compiler(<6.3)
      Compiler(series: "6.2", configuration: "602")
    #else
      fatalError("Bylaws supports Swift 6.2 through 6.5.")
    #endif
  }

  static var configuration: String {
    "Distribution/SwiftSyntax/\(compiler.configuration).json"
  }

  struct Compiler {
    let series: String
    let configuration: String
    let artifactCompilerVersion: String?

    init(
      series: String,
      configuration: String,
      artifactCompilerVersion: String? = nil
    ) {
      self.series = series
      self.configuration = configuration
      self.artifactCompilerVersion = artifactCompilerVersion
    }
  }

  enum Component: CaseIterable {
    case swift
    case c

    var target: String {
      switch self {
      case .swift:
        "BylawsSwiftSyntaxArtifact"
      case .c:
        "BylawsSwiftSyntaxCShims"
      }
    }

    var archiveName: String {
      "\(target).xcframework.zip"
    }
  }
}

private struct SwiftSyntaxArtifactConfiguration: Decodable {
  enum Mode: String, Decodable {
    case remote
    case source
  }

  let mode: Mode
  let swiftCompilerVersion: String
  let swiftSyntaxVersion: String
  let artifactRevision: Int
  let swiftArtifactChecksum: String?
  let cArtifactChecksum: String?

  var version: Version {
    guard let version = Version(swiftSyntaxVersion) else {
      fatalError("SwiftSyntax version is malformed: \(swiftSyntaxVersion)")
    }
    return version
  }

  var releaseTag: String {
    "swift-syntax-\(swiftSyntaxVersion)-\(artifactRevision)"
  }

  func checksum(for component: SwiftSyntaxArtifact.Component) -> String {
    let checksum = switch component {
    case .swift:
      swiftArtifactChecksum
    case .c:
      cArtifactChecksum
    }
    guard let checksum else {
      fatalError(
        "SwiftSyntax artifact checksum is missing for \(component.target)."
      )
    }
    return checksum
  }

  func downloadURL(for component: SwiftSyntaxArtifact.Component) -> String {
    "\(SwiftSyntaxArtifact.releaseRoot)/\(releaseTag)/\(component.archiveName)"
  }
}

private enum SwiftSyntaxSelection {
  case localArtifacts(directory: String)
  case remoteArtifacts(configuration: SwiftSyntaxArtifactConfiguration)
  case source(configuration: SwiftSyntaxArtifactConfiguration)

  static func load() -> Self {
    let configuration = loadConfiguration()

    #if os(macOS)
      if let directory = Context.environment[
        "BYLAWS_SWIFT_SYNTAX_ARTIFACTS_PATH"
      ] {
        return .localArtifacts(directory: directory)
      }
    #endif

    if Context.environment["BYLAWS_BUILD_SWIFT_SYNTAX_FROM_SOURCE"] != nil
      || Context.environment["SPI_PROCESSING"] == "1"
    {
      return .source(configuration: configuration)
    }

    #if os(macOS)
      switch configuration.mode {
      case .source:
        return .source(configuration: configuration)
      case .remote:
        guard SwiftSyntaxArtifact.compiler.artifactCompilerVersion ==
          configuration.swiftCompilerVersion
        else {
          return .source(configuration: configuration)
        }
        return .remoteArtifacts(
          configuration: configuration
        )
      }
    #else
      return .source(configuration: configuration)
    #endif
  }

  private static func loadConfiguration()
    -> SwiftSyntaxArtifactConfiguration
  {
    let manifestDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
    let configurationURL = manifestDirectory
      .appendingPathComponent(SwiftSyntaxArtifact.configuration)
    do {
      let configuration = try JSONDecoder().decode(
        SwiftSyntaxArtifactConfiguration.self,
        from: Data(contentsOf: configurationURL)
      )
      let compilerSeries = SwiftSyntaxArtifact.compiler.series
      guard configuration.swiftCompilerVersion == compilerSeries
        || configuration.swiftCompilerVersion
        .hasPrefix("\(compilerSeries).")
      else {
        fatalError(
          "SwiftSyntax configuration must match Swift \(SwiftSyntaxArtifact.compiler.series)."
        )
      }
      guard let expectedMajor = Int(
        SwiftSyntaxArtifact.compiler.configuration
      ), configuration.version.major == expectedMajor
      else {
        fatalError(
          "SwiftSyntax version must match Swift \(SwiftSyntaxArtifact.compiler.series)."
        )
      }
      return configuration
    } catch {
      fatalError("Cannot read \(SwiftSyntaxArtifact.configuration): \(error)")
    }
  }

  var dependencies: [Target.Dependency] {
    switch self {
    case .localArtifacts, .remoteArtifacts:
      SwiftSyntaxArtifact.Component.allCases.map { .target(name: $0.target) }
    case .source:
      [
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftOperators", package: "swift-syntax"),
      ]
    }
  }

  var swiftSettings: [SwiftSetting] {
    switch self {
    case .localArtifacts, .remoteArtifacts:
      [.define("BYLAWS_PREBUILT_SWIFT_SYNTAX")]
    case .source:
      []
    }
  }

  var packageDependency: Package.Dependency? {
    switch self {
    case .localArtifacts, .remoteArtifacts:
      nil
    case let .source(configuration):
      if configuration.version.prereleaseIdentifiers.isEmpty {
        .package(
          url: SwiftSyntaxArtifact.sourcePackage,
          SwiftSyntaxArtifact.minimumSourceVersion..<Version(
            configuration.version.major + 1,
            0,
            0
          )
        )
      } else {
        .package(
          url: SwiftSyntaxArtifact.sourcePackage,
          exact: configuration.version
        )
      }
    }
  }

  var binaryTargets: [Target] {
    switch self {
    case let .localArtifacts(directory):
      SwiftSyntaxArtifact.Component.allCases.map { component in
        .binaryTarget(
          name: component.target,
          path: "\(directory)/\(component.target).xcframework"
        )
      }
    case let .remoteArtifacts(configuration):
      SwiftSyntaxArtifact.Component.allCases.map { component in
        .binaryTarget(
          name: component.target,
          url: configuration.downloadURL(for: component),
          checksum: configuration.checksum(for: component)
        )
      }
    case .source:
      []
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
private let swiftSyntax = SwiftSyntaxSelection.load()

let package = Package(
  name: "swift-bylaws",
  platforms: [.macOS(.v14), .iOS(.v13)],
  products: [
    .library(name: "Bylaws", targets: ["Bylaws", "BylawsSyntax"]),
    .library(name: "BylawsCore", targets: ["BylawsCore"]),
    .library(name: "BylawsSemantics", targets: ["BylawsSemantics"]),
    .library(name: "BylawsIndexStore", targets: ["BylawsIndexStore"]),
    .library(
      name: "BylawsIndex",
      targets: ["BylawsIndex", "BylawsIndexStore"]
    ),
    .library(name: "BylawsInterpreter", targets: ["BylawsInterpreter"]),
    .library(name: "BylawsSyntax", targets: ["BylawsSyntax"]),
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
      name: "BylawsSyntax",
      dependencies: swiftSyntax.dependencies,
      swiftSettings: swiftSettings + swiftSyntax.swiftSettings
    ),
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
        "BylawsSyntax",
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
        "BylawsSyntax",
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
        "BylawsSyntax",
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
        "BylawsSyntax",
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
        "BylawsSyntax",
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
        .product(
          name: "SKLogging",
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

if let swiftSyntaxPackageDependency = swiftSyntax.packageDependency {
  package.dependencies.append(swiftSyntaxPackageDependency)
}

package.targets.append(contentsOf: swiftSyntax.binaryTargets)

if Context.environment["BYLAWS_BUILD_DOCS"] != nil {
  package.dependencies.append(
    .package(
      url: "https://github.com/swiftlang/swift-docc-plugin",
      exact: "1.5.0"
    )
  )
}
