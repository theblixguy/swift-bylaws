extension PackageManifest.Target {
  /// The operation that a plugin target performs.
  public enum PluginCapability: Sendable, Hashable, Codable {
    /// A plugin that runs during a build.
    case buildTool

    /// A plugin that runs as a package command.
    case command(intent: PluginIntent, permissions: [PluginPermission])
  }

  /// The declared purpose of a command plugin.
  ///
  /// Later versions may add cases.
  @nonexhaustive
  public enum PluginIntent: Sendable, Hashable, Codable {
    /// Generates documentation.
    case documentationGeneration

    /// Formats source code.
    case sourceCodeFormatting

    /// A package-defined command.
    case custom(verb: String, description: String)
  }

  /// Access that a command plugin requests.
  ///
  /// Later versions may add cases.
  @nonexhaustive
  public enum PluginPermission: Sendable, Hashable, Codable {
    /// Writes files inside the package directory.
    case writeToPackageDirectory(reason: String)

    /// Opens network connections.
    case allowNetworkConnections(scope: NetworkScope, reason: String)
  }

  /// The network endpoints that a plugin may connect to.
  ///
  /// Later versions may add cases.
  @nonexhaustive
  public enum NetworkScope: Sendable, Hashable, Codable {
    /// No network endpoints.
    case none

    /// Local endpoints on the selected ports.
    case local(ports: NetworkPorts)

    /// Any endpoint on the selected ports.
    case all(ports: NetworkPorts)

    /// Docker's local socket.
    case docker

    /// A Unix domain socket.
    case unixDomainSocket
  }

  /// Ports available to a plugin.
  public enum NetworkPorts: Sendable, Hashable, Codable {
    /// Individual port numbers.
    case values([Int])

    /// A half-open range of port numbers.
    case range(from: Int, upTo: Int)
  }
}
