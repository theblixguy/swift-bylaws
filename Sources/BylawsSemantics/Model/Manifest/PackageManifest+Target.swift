import Foundation

extension PackageManifest {
  /// One target declared in a `Package.swift` file.
  public struct Target: Sendable, Hashable, Codable {
    /// A SwiftPM target declaration form.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
      /// A library or regular target declared with `.target`.
      case regular

      /// An executable target declared with `.executableTarget`.
      case executable

      /// A compiler macro target declared with `.macro`.
      case macro

      /// A test target declared with `.testTarget`.
      case test

      /// A system library target declared with `.systemLibrary`.
      case systemLibrary

      /// A binary target declared with `.binaryTarget`.
      case binary

      /// A command or build tool plugin declared with `.plugin`.
      case plugin
    }

    /// A dependency declared by a target.
    public struct Dependency: Sendable, Hashable, Codable {
      /// How SwiftPM resolves the dependency name.
      ///
      /// Later versions may add cases.
      @nonexhaustive
      public enum Kind: String, CaseIterable, Sendable, Hashable, Codable {
        /// A target in this package.
        case target

        /// A product from another package.
        case product

        /// A name that SwiftPM resolves as a target or product.
        case byName
      }

      /// The target or product name.
      public let name: String

      /// How SwiftPM resolves ``name``.
      public let kind: Kind

      /// The package identity for a product dependency.
      public let packageName: String?

      /// Product module names and their local aliases.
      public let moduleAliases: [String: String]

      /// The condition that controls the dependency.
      public let condition: Condition?

      /// Dependency fields that static analysis could not resolve.
      public let unresolvedValues: [PackageManifest.UnresolvedValue]

      /// Whether every dependency field was resolved.
      public var isComplete: Bool { unresolvedValues.isEmpty }

      /// Creates a target-dependency record.
      public init(
        name: String,
        kind: Kind = .byName,
        packageName: String? = nil,
        moduleAliases: [String: String] = [:],
        condition: Condition? = nil,
        unresolvedValues: [PackageManifest.UnresolvedValue] = []
      ) {
        self.name = name
        self.kind = kind
        self.packageName = packageName
        self.moduleAliases = moduleAliases
        self.condition = condition
        self.unresolvedValues = unresolvedValues
      }
    }

    /// A resource rule declared by a target.
    public struct Resource: Sendable, Hashable, Codable {
      /// How SwiftPM adds the resource to the target.
      ///
      /// The manifest API calls this the resource's rule.
      ///
      /// Later versions may add cases.
      @nonexhaustive
      public enum BuildRule: String, CaseIterable, Sendable, Hashable, Codable {
        /// Processes the resource for the destination platform.
        case process

        /// Copies the resource without processing it.
        case copy

        /// Embeds the resource in generated source code.
        case embedInCode
      }

      /// The resource path relative to the target.
      public let path: String

      /// How SwiftPM adds the resource.
      public let rule: BuildRule

      /// The resource's localisation mode.
      public let localization: String?

      /// Creates a target-resource record.
      public init(path: String, rule: BuildRule, localization: String? = nil) {
        self.path = path
        self.rule = rule
        self.localization = localization
      }
    }

    /// A package manager that supplies a system library.
    public struct SystemPackageProvider: Sendable, Hashable, Codable {
      /// A supported system package manager.
      ///
      /// Later versions may add cases.
      @nonexhaustive
      public enum Kind: String, CaseIterable, Sendable, Hashable, Codable {
        /// Homebrew.
        case brew

        /// Advanced Package Tool.
        case apt

        /// Yellowdog Updater, Modified.
        case yum

        /// NuGet.
        case nuget
      }

      /// The package manager.
      public let kind: Kind

      /// The packages to install.
      public let packages: [String]

      /// Creates a system-package provider record.
      public init(kind: Kind, packages: [String]) {
        self.kind = kind
        self.packages = packages
      }
    }

    /// A plugin used while building the target.
    public struct PluginUsage: Sendable, Hashable, Codable {
      /// The plugin product name.
      public let name: String

      /// The package that supplies the plugin.
      public let packageName: String?

      /// Creates a plugin-usage record.
      public init(name: String, packageName: String? = nil) {
        self.name = name
        self.packageName = packageName
      }
    }

    /// The source of a binary target.
    public enum BinarySource: Sendable, Hashable, Codable {
      /// A binary stored in the package repository.
      case path(String)

      /// A downloadable binary and its checksum.
      case remote(url: String, checksum: String)
    }

    /// How SwiftPM selects source files for a target.
    public enum SourceSelection: Sendable, Hashable, Codable {
      /// SwiftPM discovers source files automatically.
      case automatic

      /// The manifest supplies source paths.
      case explicit(ManifestList<String>)
    }

    /// The target's name as written in the manifest.
    public let name: String

    /// The declaration form used for this target.
    public let kind: Kind

    /// The target dependencies, in declaration order.
    public let dependencies: ManifestList<Dependency>

    /// The dependency names, in declaration order.
    public var dependencyNames: ManifestList<String> {
      ManifestList(
        knownValues: dependencies.knownValues.map(\.name),
        conditionalValues: dependencies.conditionalValues.map(\.name),
        unresolvedValues: dependencies.unresolvedValues
      )
    }

    /// The path from the manifest's `path` argument.
    public let path: String?

    /// Paths that SwiftPM excludes from the target.
    public let excludedPaths: ManifestList<String>

    /// How SwiftPM selects source files.
    public let sources: SourceSelection

    /// The resources that belong to the target.
    public let resources: ManifestList<Resource>

    /// The target's public header directory.
    public let publicHeadersPath: String?

    /// Whether declarations with package access can cross target boundaries.
    public let packageAccess: Bool

    /// The target's compiler and linker settings.
    public let buildSettings: ManifestList<Setting>

    /// The plugins used while building the target.
    public let plugins: ManifestList<PluginUsage>

    /// The source of a binary target.
    public let binarySource: BinarySource?

    /// The `pkg-config` name for a system library target.
    public let pkgConfig: String?

    /// The package managers that can install a system library.
    public let providers: ManifestList<SystemPackageProvider>

    /// The capability of a plugin target.
    public let pluginCapability: PluginCapability?

    /// Scalar target fields that static analysis could not resolve.
    public let unresolvedValues: [PackageManifest.UnresolvedValue]

    /// Whether every target field was resolved.
    public var isComplete: Bool {
      unresolvedValues.isEmpty
        && dependencies.isComplete
        && dependencies.knownValues.allSatisfy(\.isComplete)
        && excludedPaths.isComplete
        && resources.isComplete
        && buildSettings.isComplete
        && plugins.isComplete
        && providers.isComplete
        && sources.isComplete
    }

    /// Whether the manifest declares this target with `.testTarget`.
    public var isTest: Bool { kind == .test }

    /// Whether the manifest declares this target with `.plugin`.
    public var isPlugin: Bool { kind == .plugin }

    /// Creates a target record.
    public init(
      name: String,
      dependencies: ManifestList<Dependency> = .init(),
      path: String? = nil,
      kind: Kind = .regular,
      excludedPaths: ManifestList<String> = .init(),
      sources: SourceSelection = .automatic,
      resources: ManifestList<Resource> = .init(),
      publicHeadersPath: String? = nil,
      packageAccess: Bool = true,
      buildSettings: ManifestList<Setting> = .init(),
      plugins: ManifestList<PluginUsage> = .init(),
      binarySource: BinarySource? = nil,
      pkgConfig: String? = nil,
      providers: ManifestList<SystemPackageProvider> = .init(),
      pluginCapability: PluginCapability? = nil,
      unresolvedValues: [PackageManifest.UnresolvedValue] = []
    ) {
      self.name = name
      self.dependencies = dependencies
      self.path = path
      self.kind = kind
      self.excludedPaths = excludedPaths
      self.sources = sources
      self.resources = resources
      self.publicHeadersPath = publicHeadersPath
      self.packageAccess = packageAccess
      self.buildSettings = buildSettings
      self.plugins = plugins
      self.binarySource = binarySource
      self.pkgConfig = pkgConfig
      self.providers = providers
      self.pluginCapability = pluginCapability
      self.unresolvedValues = unresolvedValues
    }

    /// The module name a Swift file imports.
    ///
    /// SwiftPM replaces characters rejected by C99 identifiers with
    /// underscores. For example, the target `my-app` produces the module
    /// `my_app`.
    public var moduleName: String {
      var mangled = String(String.UnicodeScalarView(name.unicodeScalars.map {
        CharacterSet.alphanumerics.contains($0) || $0 == "_" ? $0 : "_"
      }))
      if let first = mangled.unicodeScalars.first,
         CharacterSet.decimalDigits.contains(first)
      {
        mangled = "_\(mangled)"
      }
      return mangled
    }

    /// The normalised target source directory relative to the package root.
    public var sourceDirectory: String {
      let written = path ?? "\(defaultDirectory)/\(name)"
      var directory = Substring(written)
      while directory.hasSuffix("/") { directory = directory.dropLast() }
      while directory.hasPrefix("./") { directory = directory.dropFirst(2) }
      while directory.hasPrefix("/") { directory = directory.dropFirst() }
      return directory == "." ? "" : String(directory)
    }

    private var defaultDirectory: String {
      switch kind {
      case .test: "Tests"
      case .plugin: "Plugins"
      default: "Sources"
      }
    }
  }
}

extension PackageManifest.Target.SourceSelection {
  /// Whether static analysis resolved every explicit source path.
  public var isComplete: Bool {
    switch self {
    case .automatic: true
    case let .explicit(paths): paths.isComplete
    }
  }
}
