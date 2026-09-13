extension PackageManifest {
  /// The circumstances in which a dependency or build setting applies.
  public struct Condition: Sendable, Hashable, Codable {
    /// A SwiftPM build configuration.
    public enum Configuration: String, CaseIterable, Sendable, Hashable,
      Codable
    {
      /// A debug build.
      case debug

      /// A release build.
      case release
    }

    /// The platform names that activate the value.
    public let platforms: Set<String>

    /// The build configuration that activates the value.
    public let configuration: Configuration?

    /// The package traits that activate the value.
    public let traitNames: Set<String>

    /// Creates a manifest condition.
    public init(
      platforms: Set<String> = [],
      configuration: Configuration? = nil,
      traitNames: Set<String> = []
    ) {
      self.platforms = platforms
      self.configuration = configuration
      self.traitNames = traitNames
    }
  }
}
