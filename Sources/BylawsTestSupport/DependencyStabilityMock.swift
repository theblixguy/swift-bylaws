/// Source samples for dependency-stability tests.
public enum DependencyStabilityMock {
  /// Returns a package manifest containing one unstable dependency edge.
  ///
  /// `Core` depends on the less-stable `Utils` target. The other targets create
  /// the incoming and outgoing edges used to calculate distinct instability
  /// values.
  ///
  /// - Parameters:
  ///   - toolsVersion: The Swift tools version written into the manifest.
  ///   - packageName: The package name written into the manifest.
  public static func manifest(
    toolsVersion: String,
    packageName: String
  ) -> String {
    """
    // swift-tools-version: \(toolsVersion)
    import PackageDescription

    let package = Package(
      name: "\(packageName)",
      targets: [
        .target(name: "Logging"),
        .target(name: "Utils", dependencies: ["Logging"]),
        .target(name: "Core", dependencies: ["Utils"]),
        .target(name: "Data", dependencies: ["Core"]),
        .target(name: "UI", dependencies: ["Core"]),
      ]
    )
    """
  }
}
