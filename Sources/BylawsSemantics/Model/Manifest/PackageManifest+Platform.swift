extension PackageManifest {
  /// A deployment platform supported by the package.
  public struct Platform: Sendable, Hashable, Codable {
    /// The SwiftPM platform name.
    public let name: String

    /// The minimum supported version.
    public let minimumVersion: PlatformVersion

    /// Creates a supported-platform record.
    public init(name: String, minimumVersion: PlatformVersion) {
      self.name = name
      self.minimumVersion = minimumVersion
    }
  }
}
