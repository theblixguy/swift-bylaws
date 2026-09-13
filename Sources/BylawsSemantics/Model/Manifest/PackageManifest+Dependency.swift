extension PackageManifest {
  /// A package dependency declared in a `Package.swift` file.
  public struct Dependency: Sendable, Hashable, Codable {
    /// Where SwiftPM obtains a package dependency.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum Source: Sendable, Hashable, Codable {
      /// A source-control repository URL.
      case url(String)

      /// A local package path.
      case path(String)

      /// A package-registry identity.
      case registryIdentity(String)
    }

    /// A package dependency's source requirement.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum Requirement: Sendable, Hashable, Codable {
      /// One semantic version.
      case exact(Version)

      /// A half-open semantic-version range.
      case range(from: Version, upTo: Version)

      /// A closed semantic-version range.
      case closedRange(from: Version, through: Version)

      /// Versions from the given value up to the next major version.
      case upToNextMajor(from: Version)

      /// Versions from the given value up to the next minor version.
      case upToNextMinor(from: Version)

      /// A source-control branch.
      case branch(String)

      /// A source-control revision.
      case revision(String)

      /// A local package with no version selection.
      case local

      /// Whether the requirement selects one semantic version.
      public var isExactVersion: Bool {
        if case .exact = self { return true }
        return false
      }

      /// The minimum version selected by a version requirement.
      public var minimumVersion: Version? {
        switch self {
        case let .exact(version),
             let .range(from: version, upTo: _),
             let .closedRange(from: version, through: _),
             let .upToNextMajor(from: version),
             let .upToNextMinor(from: version):
          version
        case .branch, .revision, .local:
          nil
        }
      }

      /// The minimum version's major component.
      public var majorVersion: Int? {
        minimumVersion?.major
      }
    }

    /// The declared name, or the final component of the source location.
    public let name: String

    /// Where SwiftPM obtains the package.
    public let source: Source

    /// The package's version, branch, revision or local source.
    public let requirement: Requirement

    /// The dependency traits selected by this declaration.
    public let traits: ManifestList<TraitSelection>

    /// Creates a package-dependency record.
    public init(
      name: String,
      source: Source,
      requirement: Requirement,
      traits: ManifestList<TraitSelection> = .init(
        knownValues: [.defaults]
      )
    ) {
      self.name = name
      self.source = source
      self.requirement = requirement
      self.traits = traits
    }
  }
}
