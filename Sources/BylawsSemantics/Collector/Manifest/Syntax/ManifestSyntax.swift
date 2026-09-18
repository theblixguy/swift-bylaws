import BylawsSyntax

enum ManifestCallName: String {
  case all
  case allowNetworkConnections
  case binaryTarget
  case buildTool
  case byName
  case command
  case copy
  case custom
  case defaultIsolation
  case defaultTrait = "default"
  case define
  case disableWarning
  case documentationGeneration
  case embedInCode
  case enableExperimentalFeature
  case enableUpcomingFeature
  case enableWarning
  case exact
  case executable
  case executableTarget
  case headerSearchPath
  case interoperabilityMode
  case library
  case linkedFramework
  case linkedLibrary
  case local
  case macro
  case package
  case plugin
  case process
  case product
  case sourceCodeFormatting
  case strictMemorySafety
  case swiftLanguageMode
  case swiftLanguageVersion
  case systemLibrary
  case target
  case testTarget
  case trait
  case treatAllWarnings
  case treatWarning
  case unsafeFlags
  case upToNextMajor
  case upToNextMinor
  case when
  case writeToPackageDirectory

  var isTargetFactory: Bool {
    switch self {
    case .target, .executableTarget, .macro, .testTarget, .systemLibrary,
         .binaryTarget, .plugin:
      true
    default:
      false
    }
  }
}

enum ManifestPackageField: String, CaseIterable {
  case dependencies
  case platforms
  case products
  case swiftLanguageModes
  case swiftLanguageVersions
  case targets
  case traits
  case cLanguageStandard
  case cxxLanguageStandard
  case defaultLocalization
  case name

  var isCollection: Bool {
    switch self {
    case .dependencies, .platforms, .products, .swiftLanguageModes,
         .swiftLanguageVersions, .targets, .traits:
      true
    case .cLanguageStandard, .cxxLanguageStandard, .defaultLocalization,
         .name:
      false
    }
  }
}

enum ManifestCollectionMutation: String {
  case append
  case insert
  case remove
  case removeAll
  case removeFirst
  case removeLast
  case replaceSubrange
  case shuffle
  case sort
}

enum ManifestTargetField: String, CaseIterable {
  case cSettings
  case cxxSettings
  case dependencies
  case exclude
  case linkerSettings
  case packageAccess
  case path
  case plugins
  case publicHeadersPath
  case resources
  case sources
  case swiftSettings
}

enum ManifestEnumType: String {
  case buildConfiguration = "BuildConfiguration"
  case cLanguageStandard = "CLanguageStandard"
  case cxxLanguageStandard = "CXXLanguageStandard"
  case interoperabilityMode = "InteroperabilityMode"
  case libraryType = "LibraryType"
  case localization = "Localization"
  case platform = "Platform"
  case swiftLanguageMode = "SwiftLanguageMode"
  case swiftVersion = "SwiftVersion"
  case warningLevel = "WarningLevel"
}

extension ExprSyntax {
  var manifestAccessPath: [String]? {
    if let reference = `as`(DeclReferenceExprSyntax.self) {
      return [reference.baseName.text]
    }
    guard let member = `as`(MemberAccessExprSyntax.self) else { return nil }
    guard let base = member.base else {
      return [member.declName.baseName.text]
    }
    guard let path = base.manifestAccessPath else { return nil }
    return path + [member.declName.baseName.text]
  }
}

extension FunctionCallExprSyntax {
  var manifestAccessPath: [String]? {
    calledExpression.manifestAccessPath
  }

  var manifestCallName: ManifestCallName? {
    guard let path = manifestAccessPath, path.count == 1 else { return nil }
    return ManifestCallName(rawValue: path[0])
  }

  var isManifestPackageInitializer: Bool {
    guard let path = manifestAccessPath else { return false }
    return path == ["Package"]
      || path == ["Package", "init"]
      || path == ["PackageDescription", "Package"]
  }

  var isManifestSetInitializer: Bool {
    guard let path = manifestAccessPath else { return false }
    return path == ["Set"] || path == ["Swift", "Set"]
  }
}

func manifestMemberNames(in syntax: some SyntaxProtocol) -> Set<String> {
  let collector = ManifestMemberNameCollector(viewMode: .sourceAccurate)
  collector.walk(Syntax(syntax))
  return collector.names
}

func manifestReferenceNames(in syntax: some SyntaxProtocol) -> Set<String> {
  let collector = ManifestReferenceNameCollector(viewMode: .sourceAccurate)
  collector.walk(Syntax(syntax))
  return collector.names
}

private final class ManifestMemberNameCollector: SyntaxVisitor {
  private(set) var names: Set<String> = []

  override func visit(_ node: MemberAccessExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    names.insert(node.declName.baseName.text)
    return .visitChildren
  }
}

private final class ManifestReferenceNameCollector: SyntaxVisitor {
  private(set) var names: Set<String> = []

  override func visit(_ node: DeclReferenceExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    names.insert(node.baseName.text)
    return .skipChildren
  }
}
