import BylawsPaths
package import Foundation

package enum ParseCachePolicy: Sendable, Hashable {
  package struct Settings: Sendable {
    package let directory: URL
    package let budget: Int
    package let validation: ParseCacheConfiguration.Validation
  }

  package static let disableEnvironmentKey = "BYLAWS_DISABLE_PARSE_CACHE"
  package static let directoryEnvironmentKey = "BYLAWS_CACHE_PATH"

  case disabled
  case enabled(
    directory: URL, cachesTemporaryRoots: Bool,
    budget: Int = ParseCacheConfiguration.defaultBudget,
    validation: ParseCacheConfiguration.Validation = .metadata
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
    if case .environment = self,
       let configuration = ParseCacheConfiguration.current
    {
      return Self.configured(configuration).resolved(
        environment: environment, defaultCacheDirectory: defaultCacheDirectory
      )
    }
    if case let .configured(configuration) = self {
      guard configuration.budget > 0 else { return .disabled }
      if let directory = configuration.directory {
        return .enabled(
          directory: directory, cachesTemporaryRoots: true,
          budget: configuration.budget, validation: configuration.validation
        )
      }
      return Self.enabled(
        cachesTemporaryRoots: true, environment: environment,
        defaultCacheDirectory: defaultCacheDirectory,
        budget: configuration.budget, validation: configuration.validation
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

  package func settings(forRoot rootPath: String) -> Settings? {
    guard case let .enabled(
      directory,
      cachesTemporaryRoots,
      budget,
      validation
    ) = resolved()
    else { return nil }
    let temporaryDirectories = [
      FileManager.default.temporaryDirectory.path,
      "/tmp", "/private/tmp", "/var/folders", "/private/var/folders",
    ]
    guard cachesTemporaryRoots
      || !temporaryDirectories.contains(where: {
        LexicalFilePath($0).contains(LexicalFilePath(rootPath))
      })
    else { return nil }
    return Settings(
      directory: directory,
      budget: budget,
      validation: validation
    )
  }

  private static func enabled(
    cachesTemporaryRoots: Bool,
    environment: [String: String],
    defaultCacheDirectory: URL?,
    budget: Int = ParseCacheConfiguration.defaultBudget,
    validation: ParseCacheConfiguration.Validation = .metadata
  ) -> ParseCachePolicy {
    if let path = environment[directoryEnvironmentKey], !path.isEmpty {
      return .enabled(
        directory: URL(fileURLWithPath: path),
        cachesTemporaryRoots: cachesTemporaryRoots, budget: budget,
        validation: validation
      )
    }
    guard let defaultCacheDirectory else { return .disabled }
    return .enabled(
      directory: defaultCacheDirectory,
      cachesTemporaryRoots: cachesTemporaryRoots, budget: budget,
      validation: validation
    )
  }
}
