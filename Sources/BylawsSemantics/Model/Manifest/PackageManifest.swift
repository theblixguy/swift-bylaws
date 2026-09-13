/// Package metadata recovered from a `Package.swift` file.
///
/// Swift package manifests are executable programs. Each collection records
/// expressions that static analysis could not resolve so rules can distinguish
/// an empty declaration from an incomplete result.
public struct PackageManifest: Sendable, Hashable, Codable {
  /// The package name, when it could be resolved.
  public let name: String?

  /// The tools version from the manifest header.
  public let toolsVersion: ToolsVersion?

  /// The package's default localisation.
  public let defaultLocalization: String?

  /// The platforms supported by the package.
  public let platforms: ManifestList<Platform>

  /// The products exported by the package.
  public let products: ManifestList<Product>

  /// The package traits available to clients.
  public let traits: ManifestList<Trait>

  /// Traits enabled by the package's default trait group.
  public let defaultTraitNames: ManifestList<String>

  /// The package dependencies, in declaration order.
  public let dependencies: ManifestList<Dependency>

  /// The targets, in declaration order.
  public let targets: ManifestList<Target>

  /// The supported Swift language modes.
  public let swiftLanguageModes: ManifestList<String>

  /// The C language standard selected by the package.
  public let cLanguageStandard: String?

  /// The C++ language standard selected by the package.
  public let cxxLanguageStandard: String?

  /// Unresolved scalar fields and package-level mutations.
  public let unresolvedValues: [UnresolvedValue]

  /// Whether every requested manifest value was resolved.
  public var isComplete: Bool {
    unresolvedValues.isEmpty
      && platforms.isComplete
      && products.isComplete
      && products.knownValues.allSatisfy(\.isComplete)
      && traits.isComplete
      && defaultTraitNames.isComplete
      && dependencies.isComplete
      && dependencies.knownValues.allSatisfy(\.traits.isComplete)
      && targets.isComplete
      && targets.knownValues.allSatisfy(\.isComplete)
      && swiftLanguageModes.isComplete
  }

  /// Creates a manifest record.
  public init(
    name: String? = nil,
    toolsVersion: ToolsVersion? = nil,
    defaultLocalization: String? = nil,
    platforms: ManifestList<Platform> = .init(),
    products: ManifestList<Product> = .init(),
    traits: ManifestList<Trait> = .init(),
    defaultTraitNames: ManifestList<String> = .init(),
    dependencies: ManifestList<Dependency> = .init(),
    targets: ManifestList<Target>,
    swiftLanguageModes: ManifestList<String> = .init(),
    cLanguageStandard: String? = nil,
    cxxLanguageStandard: String? = nil,
    unresolvedValues: [UnresolvedValue] = []
  ) {
    self.name = name
    self.toolsVersion = toolsVersion
    self.defaultLocalization = defaultLocalization
    self.platforms = platforms
    self.products = products
    self.traits = traits
    self.defaultTraitNames = defaultTraitNames
    self.dependencies = dependencies
    self.targets = targets
    self.swiftLanguageModes = swiftLanguageModes
    self.cLanguageStandard = cLanguageStandard
    self.cxxLanguageStandard = cxxLanguageStandard
    self.unresolvedValues = unresolvedValues
  }

  /// Creates a manifest record from resolved targets and dependencies.
  public init(
    targets: [Target],
    dependencies: [Dependency] = []
  ) {
    self.init(
      dependencies: ManifestList(knownValues: dependencies),
      targets: ManifestList(knownValues: targets)
    )
  }

  /// Reads package metadata without executing the manifest.
  public init(source: String) {
    self = ManifestCollector.manifest(in: source)
  }

  /// Returns dependencies with the given name.
  public func dependencies(named name: String) -> ManifestList<Dependency> {
    dependencies.filtering { $0.name == name }
  }

  /// Returns targets with the given name.
  public func targets(named name: String) -> ManifestList<Target> {
    targets.filtering { $0.name == name }
  }

  /// Returns products with the given name.
  public func products(named name: String) -> ManifestList<Product> {
    products.filtering { $0.name == name }
  }

  /// Returns the products that contain the target.
  public func products(containing target: Target) -> ManifestList<Product> {
    var known: [Product] = []
    var conditional: [Product] = []
    var unresolved = products.unresolvedValues
    for product in products.knownValues {
      unresolved.append(contentsOf: product.targetNames.unresolvedValues)
      if product.targetNames.knownValues.contains(target.name) {
        known.append(product)
      } else if product.targetNames.conditionalValues.contains(target.name) {
        conditional.append(product)
      }
    }
    for product in products.conditionalValues {
      unresolved.append(contentsOf: product.targetNames.unresolvedValues)
      if product.targetNames.possibleValues.contains(target.name) {
        conditional.append(product)
      }
    }
    return ManifestList(
      knownValues: known,
      conditionalValues: conditional,
      unresolvedValues: unresolved
    )
  }
}

extension ManifestList {
  fileprivate func filtering(_ includes: (Element) -> Bool) -> Self {
    Self(
      knownValues: knownValues.filter(includes),
      conditionalValues: conditionalValues.filter(includes),
      unresolvedValues: unresolvedValues
    )
  }
}
