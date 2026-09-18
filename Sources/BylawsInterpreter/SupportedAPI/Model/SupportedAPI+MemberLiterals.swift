import BylawsCore
package import BylawsSemantics

extension SupportedAPI {
  // A leading-dot literal reaches the parser as a bare name.
  package enum MemberLiteral: Hashable, Sendable {
    case matcher(Matcher.ID)
    case constant(Constant)
    case sourceNodeKind(SourceNode.Kind)

    package enum Constant: String, CaseIterable, Hashable, Sendable {
      case any
      case advisory
      case enforced

      case `private`
      case `fileprivate`
      case `internal`
      case package
      case `public`
      case open

      case weak
      case unowned

      case `struct`
      case `class`
      case actor
      case `enum`
      case `protocol`
      case `typealias`
      case `func`
      case `var`
      case `let`

      case module
      case `extension`
      case function
      case variable
      case instanceMethod
      case classMethod
      case staticMethod
      case instanceProperty
      case classProperty
      case staticProperty
      case initializer
      case deinitializer
      case enumCase
      case parameter
      case other

      case declaration
      case definition
      case reference
      case read
      case write
      case call
      case dynamic
      case implicit
      case childOf
      case baseOf
      case overrideOf
      case receivedBy
      case calledBy
      case extendedBy
      case accessorOf
      case containedBy
      case specializationOf

      case sourceAccurate

      case library
      case executable
      case plugin
      case automatic
      case `static`

      case url
      case path
      case registryIdentity
      case exact
      case range
      case closedRange
      case upToNextMajor
      case upToNextMinor
      case branch
      case revision
      case local
      case defaults

      case regular
      case macro
      case test
      case systemLibrary
      case binary
      case target
      case product
      case byName
      case explicit

      case process
      case copy
      case embedInCode
      case swift
      case c
      case cxx
      case linker
      case define
      case unsafeFlags
      case headerSearchPath
      case enableUpcomingFeature
      case enableExperimentalFeature
      case strictMemorySafety
      case interoperabilityMode
      case swiftLanguageMode
      case treatAllWarnings
      case treatWarning
      case enableWarning
      case disableWarning
      case defaultIsolation
      case linkedLibrary
      case linkedFramework
      case warning
      case error
      case mainActor
      case debug
      case release

      case brew
      case apt
      case yum
      case nuget

      case buildTool
      case command
      case documentationGeneration
      case sourceCodeFormatting
      case custom
      case writeToPackageDirectory
      case allowNetworkConnections
      case none
      case all
      case docker
      case unixDomainSocket
      case values
      case remote
    }
  }

  package static let memberLiteralNames: Set<String> =
    Set(MemberLiteral.allCases.map(\.rawValue))
}

extension SupportedAPI.MemberLiteral: RawRepresentable, CaseIterable {
  package init?(rawValue: String) {
    if let constant = Constant(rawValue: rawValue) {
      self = .constant(constant)
    } else if let matcher = SupportedAPI.Matcher.ID(rawValue: rawValue) {
      self = .matcher(matcher)
    } else if let kind = SourceNode.Kind(rawValue: rawValue) {
      self = .sourceNodeKind(kind)
    } else {
      return nil
    }
  }

  package var rawValue: String {
    switch self {
    case let .matcher(id): id.rawValue
    case let .constant(constant): constant.rawValue
    case let .sourceNodeKind(kind): kind.rawValue
    }
  }

  package static var allCases: [Self] {
    SupportedAPI.Matcher.ID.allCases.map(matcher)
      + Constant.allCases.map(constant)
      + SourceNode.Kind.allCases.map(sourceNodeKind)
  }
}

extension SupportedAPI.MemberLiteral {
  // A name may belong to more than one owner, so `.dynamic` is a symbol role
  // and a library linkage at once.
  package enum Owner: CaseIterable, Hashable, Sendable {
    case layerImportPolicy
    case enforcement
    case visibility
    case ownership
    case importKind
    case indexSymbolKind
    case sourceNodeKind
    case symbolRole
    case matcher
    case tokenViewMode
    case productKind
    case libraryLinkage
    case dependencySource
    case dependencyRequirement
    case traitKind
    case targetKind
    case targetDependencyKind
    case resourceRule
    case systemPackageProviderKind
    case binarySource
    case sourceSelection
    case settingTool
    case settingValue
    case warningLevel
    case defaultIsolation
    case conditionConfiguration
    case pluginCapability
    case pluginIntent
    case pluginPermission
    case networkScope
    case networkPorts
  }

  package var owners: Set<Owner> { Self.ownersByLiteral[self] ?? [] }

  private static let ownersByLiteral: [Self: Set<Owner>] = {
    var table: [Self: Set<Owner>] = [:]
    for owner in Owner.allCases {
      for literal in owner
        .literals { table[literal, default: []].insert(owner) }
    }
    return table
  }()
}

extension SupportedAPI {
  package enum StaticMemberType: String, CaseIterable, Hashable, Sendable {
    case importKind = "ImportKind"
    case indexSymbolKind = "IndexSymbol.Kind"
    case sourceNodeKind = "SourceNode.Kind"
    case ownership = "Ownership"
    case symbolRole = "SymbolRole"
    case visibility = "Visibility"

    package var owner: MemberLiteral.Owner {
      switch self {
      case .importKind: .importKind
      case .indexSymbolKind: .indexSymbolKind
      case .sourceNodeKind: .sourceNodeKind
      case .ownership: .ownership
      case .symbolRole: .symbolRole
      case .visibility: .visibility
      }
    }
  }
}

extension SupportedAPI.MemberLiteral.Owner {
  package var literals: [SupportedAPI.MemberLiteral] {
    source.names.compactMap(SupportedAPI.MemberLiteral.init(rawValue:))
  }

  var sourceNames: [String] { source.names }

  private enum Source {
    case cases([String])
    case constants([SupportedAPI.MemberLiteral.Constant])
    case listed([SupportedAPI.MemberLiteral])

    init<Cases: CaseIterable & RawRepresentable<String>>(_ type: Cases.Type) {
      self = .cases(Cases.allCases.map(\.rawValue))
    }

    var names: [String] {
      switch self {
      case let .cases(names): names
      case let .constants(constants): constants.map(\.rawValue)
      case let .listed(literals): literals.map(\.rawValue)
      }
    }
  }

  // A source type that carries associated values is not CaseIterable.
  private var source: Source {
    switch self {
    case .enforcement: Source(Enforcement.self)
    case .layerImportPolicy: .constants([.any])
    case .visibility: Source(Visibility.self)
    case .ownership: Source(Ownership.self)
    case .importKind: Source(ImportKind.self)
    case .indexSymbolKind: Source(RuntimeIndexSymbol.Kind.self)
    case .sourceNodeKind: Source(SourceNode.Kind.self)
    case .symbolRole: Source(RuntimeSymbolRole.self)
    case .matcher: Source(SupportedAPI.Matcher.ID.self)
    case .tokenViewMode: .constants([.sourceAccurate])
    case .productKind: .constants([
        .library,
        .executable,
        .plugin,
      ])
    case .libraryLinkage: Source(PackageManifest.Product.LibraryLinkage.self)
    case .dependencySource: .constants([
        .url,
        .path,
        .registryIdentity,
      ])
    case .dependencyRequirement:
      .constants([
        .exact, .range, .closedRange,
        .upToNextMajor, .upToNextMinor,
        .branch,
        .revision, .local,
      ])
    // The trait kind `.named` shares its spelling with the matcher.
    case .traitKind: .listed([.constant(.defaults), .matcher(.named)])
    case .targetKind: Source(PackageManifest.Target.Kind.self)
    case .targetDependencyKind:
      Source(PackageManifest.Target.Dependency.Kind.self)
    case .resourceRule: Source(PackageManifest.Target.Resource.BuildRule.self)
    case .systemPackageProviderKind:
      Source(PackageManifest.Target.SystemPackageProvider.Kind.self)
    case .binarySource: .constants([.path, .remote])
    case .sourceSelection: .constants([
        .automatic,
        .explicit,
      ])
    case .settingTool: Source(PackageManifest.Target.Setting.Tool.self)
    case .settingValue:
      .constants([
        .define, .unsafeFlags,
        .headerSearchPath, .enableUpcomingFeature,
        .enableExperimentalFeature, .strictMemorySafety,
        .interoperabilityMode,
        .swiftLanguageMode, .treatAllWarnings,
        .treatWarning, .enableWarning,
        .disableWarning, .defaultIsolation,
        .linkedLibrary, .linkedFramework,
      ])
    case .warningLevel:
      Source(PackageManifest.Target.Setting.WarningLevel.self)
    case .defaultIsolation:
      Source(PackageManifest.Target.Setting.DefaultIsolation.self)
    case .conditionConfiguration:
      Source(PackageManifest.Condition.Configuration.self)
    case .pluginCapability: .constants([
        .buildTool,
        .command,
      ])
    case .pluginIntent:
      .constants([
        .documentationGeneration,
        .sourceCodeFormatting,
        .custom,
      ])
    case .pluginPermission:
      .constants([
        .writeToPackageDirectory,
        .allowNetworkConnections,
      ])
    case .networkScope:
      .constants([
        .none,
        .local,
        .all,
        .docker,
        .unixDomainSocket,
      ])
    case .networkPorts: .constants([.values, .range])
    }
  }
}

extension SupportedAPI.ModelType {
  var nestedStaticMemberType: SupportedAPI.StaticMemberType? {
    switch self {
    case .indexSymbol: .indexSymbolKind
    case .sourceNode: .sourceNodeKind
    default: nil
    }
  }
}
