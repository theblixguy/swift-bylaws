package import Foundation

package enum ParseCachePolicy: Sendable, Hashable {
  package static let disableEnvironmentKey = "BYLAWS_DISABLE_PARSE_CACHE"
  package static let directoryEnvironmentKey = "BYLAWS_CACHE_PATH"

  case disabled
  case enabled(
    directory: URL, cachesTemporaryRoots: Bool,
    budget: Int = ParseCacheConfiguration.defaultBudget
  )
  case configured(ParseCacheConfiguration)
  case environment(cachesTemporaryRoots: Bool = false)

  package func resolved(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    defaultCacheDirectory: URL? = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first
  ) -> ParseCachePolicy {
    if case let .configured(configuration) = self {
      guard configuration.budget > 0 else { return .disabled }
      if let directory = configuration.directory {
        return .enabled(
          directory: directory, cachesTemporaryRoots: true,
          budget: configuration.budget
        )
      }
      return Self.enabled(
        cachesTemporaryRoots: true, environment: environment,
        defaultCacheDirectory: defaultCacheDirectory,
        budget: configuration.budget
      )
    }
    guard case let .environment(cachesTemporaryRoots) = self else {
      return self
    }
    let disabled = environment[Self.disableEnvironmentKey]
    guard disabled != "true", disabled != "1" else { return .disabled }
    return Self.enabled(
      cachesTemporaryRoots: cachesTemporaryRoots,
      environment: environment,
      defaultCacheDirectory: defaultCacheDirectory
    )
  }

  private static func enabled(
    cachesTemporaryRoots: Bool,
    environment: [String: String],
    defaultCacheDirectory: URL?,
    budget: Int = ParseCacheConfiguration.defaultBudget
  ) -> ParseCachePolicy {
    if let path = environment[directoryEnvironmentKey], !path.isEmpty {
      return .enabled(
        directory: URL(fileURLWithPath: path),
        cachesTemporaryRoots: cachesTemporaryRoots, budget: budget
      )
    }
    guard let defaultCacheDirectory else { return .disabled }
    return .enabled(
      directory: defaultCacheDirectory,
      cachesTemporaryRoots: cachesTemporaryRoots, budget: budget
    )
  }
}
