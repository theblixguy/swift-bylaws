package import Foundation

package enum ParseCachePolicy: Sendable, Hashable {
  package static let disableEnvironmentKey = "BYLAWS_DISABLE_PARSE_CACHE"
  package static let directoryEnvironmentKey = "BYLAWS_CACHE_PATH"

  case disabled
  case enabled(directory: URL, cachesTemporaryRoots: Bool)
  case environment(cachesTemporaryRoots: Bool = false)

  package func resolved(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    defaultCacheDirectory: URL? = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first
  ) -> ParseCachePolicy {
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

  package static func defaultEnabled(
    cachesTemporaryRoots: Bool
  ) -> ParseCachePolicy {
    let environment = ProcessInfo.processInfo.environment
    let defaultCacheDirectory = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first
    return enabled(
      cachesTemporaryRoots: cachesTemporaryRoots,
      environment: environment,
      defaultCacheDirectory: defaultCacheDirectory
    )
  }

  private static func enabled(
    cachesTemporaryRoots: Bool,
    environment: [String: String],
    defaultCacheDirectory: URL?
  ) -> ParseCachePolicy {
    if let path = environment[directoryEnvironmentKey], !path.isEmpty {
      return .enabled(
        directory: URL(fileURLWithPath: path),
        cachesTemporaryRoots: cachesTemporaryRoots
      )
    }
    guard let defaultCacheDirectory else { return .disabled }
    return .enabled(
      directory: defaultCacheDirectory,
      cachesTemporaryRoots: cachesTemporaryRoots
    )
  }
}
