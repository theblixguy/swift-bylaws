extension BazelGraph {
  /// The build settings for a configured target.
  public struct Configuration: Sendable, Hashable {
    /// Bazel's full checksum of the configuration options.
    public let checksum: String

    /// Whether Bazel uses this configuration to build tools.
    public let isTool: Bool

    /// The exported option values, grouped by Bazel's option class name.
    ///
    /// User-defined settings are in the `user-defined` group. Values retain
    /// Bazel's string representation, including list and Boolean values.
    public let buildOptions: [String: [String: String]]
  }
}
