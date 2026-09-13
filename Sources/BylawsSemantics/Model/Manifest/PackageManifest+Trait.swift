extension PackageManifest {
  /// One optional package capability.
  public struct Trait: Sendable, Hashable, Codable {
    /// The trait name.
    public let name: String

    /// The description shown to package clients.
    public let description: String?

    /// Other traits that this trait enables.
    public let enabledTraitNames: Set<String>

    /// Creates a package-trait record.
    public init(
      name: String,
      description: String? = nil,
      enabledTraitNames: Set<String> = []
    ) {
      self.name = name
      self.description = description
      self.enabledTraitNames = enabledTraitNames
    }
  }
}

extension PackageManifest.Dependency {
  /// The traits selected for a package dependency.
  public struct TraitSelection: Sendable, Hashable, Codable {
    /// The selected trait.
    public enum Kind: Sendable, Hashable, Codable {
      /// The dependency's default traits.
      case defaults

      /// One named trait.
      case named(String)
    }

    /// The selected trait.
    public let kind: Kind

    /// The package traits that activate this selection.
    public let condition: PackageManifest.Condition?

    /// Creates a dependency-trait selection.
    public init(
      kind: Kind,
      condition: PackageManifest.Condition? = nil
    ) {
      self.kind = kind
      self.condition = condition
    }

    /// The dependency's default trait selection.
    public static let defaults = Self(kind: .defaults)
  }
}
