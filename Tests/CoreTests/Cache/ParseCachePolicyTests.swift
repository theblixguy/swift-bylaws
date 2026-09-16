import BylawsCore
import Foundation
import Testing

@Suite("Parse cache policy")
struct ParseCachePolicyTests {
  @Test("Cache policy uses environment settings at resolution time")
  func constructionDefersEnvironment() {
    let codebase = Codebase(root: .sources([:]))
    let cache = URL(fileURLWithPath: "/custom/bylaws-cache")

    #expect(codebase.parseCachePolicy == .environment())
    #expect(
      codebase.parseCachePolicy.resolved(
        environment: [ParseCachePolicy.directoryEnvironmentKey: cache.path],
        defaultCacheDirectory: nil
      ) == .enabled(directory: cache, cachesTemporaryRoots: false)
    )
    #expect(
      codebase.parseCachePolicy.resolved(
        environment: [ParseCachePolicy.disableEnvironmentKey: "true"],
        defaultCacheDirectory: cache
      ) == .disabled
    )
  }

  @Test("Equal codebases can use independent cache policies")
  func independentPolicies() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
      .appendingPathComponent("bylaws-cache-policy-\(UUID().uuidString)")
    let cache = manager.temporaryDirectory
      .appendingPathComponent("bylaws-cache-output-\(UUID().uuidString)")
    try manager.createDirectory(
      at: root.appendingPathComponent("Sources/App"),
      withIntermediateDirectories: true
    )
    defer {
      try? manager.removeItem(at: root)
      try? manager.removeItem(at: cache)
    }
    try "struct Model {}".write(
      to: root.appendingPathComponent("Sources/App/Model.swift"),
      atomically: true,
      encoding: .utf8
    )
    let codebase = Codebase(
      root: .directory(root.path),
      including: ["Sources/**"]
    )

    _ = try await codebase.usingParseCache(.disabled).files
    #expect(!manager.fileExists(atPath: cache.path))

    _ = try await codebase.usingParseCache(
      .enabled(directory: cache, cachesTemporaryRoots: true)
    ).files
    let entries = manager.enumerator(atPath: cache.path)?
      .compactMap { $0 as? String } ?? []
    #expect(entries.contains { $0.hasSuffix(".pack") })
  }

  @Test("Explicit directory and budget override environment settings")
  func explicitConfiguration() {
    let directory = URL(fileURLWithPath: "/explicit/cache")
    let codebase = Codebase(parseCache: .init(
      directory: directory,
      budget: 500
    ))
    let policy = codebase.parseCachePolicy.resolved(environment: [
      ParseCachePolicy.disableEnvironmentKey: "true",
      ParseCachePolicy.directoryEnvironmentKey: "/environment/cache",
    ])
    #expect(policy == .enabled(
      directory: directory, cachesTemporaryRoots: true, budget: 500
    ))
  }

  @Test("Budget configuration keeps environment directory")
  func environmentDirectory() {
    let policy = Codebase(parseCache: .init(budget: 500))
      .parseCachePolicy.resolved(environment: [
        ParseCachePolicy.directoryEnvironmentKey: "/environment/cache",
      ], defaultCacheDirectory: nil)
    #expect(policy == .enabled(
      directory: URL(fileURLWithPath: "/environment/cache"),
      cachesTemporaryRoots: true, budget: 500
    ))
  }

  @Test("Zero budget disables disk cache")
  func zeroBudget() {
    #expect(Codebase(parseCache: .init(budget: 0))
      .parseCachePolicy.resolved() == .disabled)
  }

  @Test("Parallel codebases keep separate cache directories and budgets")
  func parallelConfigurations() async throws {
    let first = try ParseCacheTestStorage()
    let second = try ParseCacheTestStorage()
    let source = "struct Model {}"
    let sourceURL = first.directory.appendingPathComponent("Model.swift")
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    let root = Codebase.Root.directory(first.directory.path)
    let retained = Codebase(
      root: root, including: ["Model.swift"],
      parseCache: .init(directory: first.directory)
    )
    let trimmed = Codebase(
      root: root, including: ["Model.swift"],
      parseCache: .init(directory: second.directory, budget: 1)
    )
    async let firstFiles = retained.files
    async let secondFiles = trimmed.files
    let files = try await (firstFiles, secondFiles)
    #expect(files.0.count == 1)
    #expect(files.1.count == 1)
    let firstCache = try ParseCache.opening(directory: first.directory)
    let secondCache = try ParseCache.opening(directory: second.directory)
    #expect(await firstCache
      .sourceFile(forSource: source, at: sourceURL.path) != nil)
    #expect(await secondCache
      .sourceFile(forSource: source, at: sourceURL.path) == nil)
  }

  @Test("Validation defaults to metadata and explicit choices stay independent")
  func validationChoice() {
    let directory = URL(fileURLWithPath: "/cache")
    let defaults = Codebase(parseCache: .init(directory: directory))
    let content = Codebase(parseCache: .init(
      directory: directory,
      validation: .content
    ))

    #expect(defaults.parseCachePolicy.resolved() == .enabled(
      directory: directory, cachesTemporaryRoots: true, validation: .metadata
    ))
    #expect(content.parseCachePolicy.resolved() == .enabled(
      directory: directory, cachesTemporaryRoots: true, validation: .content
    ))
  }
}
