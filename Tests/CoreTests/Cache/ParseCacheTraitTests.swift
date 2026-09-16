import Bylaws
import BylawsCore
import Foundation
import Testing

private let suiteCacheDirectory = URL(fileURLWithPath: "/suite/cache")

@Suite(
  "Parse cache traits",
  .parseCache(
    directory: suiteCacheDirectory,
    budget: 8192,
    validation: .content
  )
)
struct ParseCacheTraitTests {
  static let codebase =
    Codebase(root: .sources(["Model.swift": "class Model {}"]))

  @Test("Suite settings apply to stored codebases")
  func suiteSettings() {
    #expect(Self.codebase.parseCachePolicy.resolved() == .enabled(
      directory: suiteCacheDirectory,
      cachesTemporaryRoots: true,
      budget: 8192,
      validation: .content
    ))
  }

  @Test(
    "Validation override keeps suite directory and budget",
    .parseCache(validation: .metadata),
    arguments: [1, 2]
  )
  func validationOverride(_: Int) {
    #expect(Self.codebase.parseCachePolicy.resolved() == .enabled(
      directory: suiteCacheDirectory,
      cachesTemporaryRoots: true,
      budget: 8192,
      validation: .metadata
    ))
  }

  @Test(
    "Argument evaluation precedes cache trait scope",
    .parseCache(budget: 2048, validation: .metadata),
    arguments: [ParseCacheConfiguration.current]
  )
  func argumentScope(configuration: ParseCacheConfiguration?) {
    #expect(configuration == nil)
    #expect(ParseCacheConfiguration.current == .init(
      directory: suiteCacheDirectory, budget: 2048, validation: .metadata
    ))
  }

  @Test("Empty trait keeps suite settings", .parseCache())
  func omittedSettings() {
    #expect(ParseCacheConfiguration.current == .init(
      directory: suiteCacheDirectory, budget: 8192, validation: .content
    ))
  }

  @Test(
    "Later traits override specified fields and keep omitted settings",
    .parseCache(directory: URL(fileURLWithPath: "/test/cache"), budget: 1024),
    .parseCache(budget: 2048)
  )
  func multipleTraits() {
    #expect(ParseCacheConfiguration.current == .init(
      directory: URL(fileURLWithPath: "/test/cache"),
      budget: 2048,
      validation: .content
    ))
  }

  @Test("Zero budget disables disk caching", .parseCache(budget: 0))
  func zeroBudget() {
    #expect(Self.codebase.parseCachePolicy.resolved() == .disabled)
  }

  @Test("Codebase settings override trait settings", .parseCache(budget: 0))
  func explicitConfiguration() {
    let directory = URL(fileURLWithPath: "/explicit/cache")
    let codebase = Codebase(parseCache: .init(directory: directory))
    #expect(codebase.parseCachePolicy.resolved() == .enabled(
      directory: directory,
      cachesTemporaryRoots: true,
      budget: ParseCacheConfiguration.defaultBudget,
      validation: .metadata
    ))
  }

  @Suite("Nested cache settings", .parseCache(budget: 4096))
  struct Nested {
    @Test("Nested suite inherits directory and validation")
    func inheritance() {
      #expect(ParseCacheConfiguration.current == .init(
        directory: suiteCacheDirectory,
        budget: 4096,
        validation: .content
      ))
    }

    @Test("Test overrides nearest suite", .parseCache(validation: .metadata))
    func override() {
      #expect(ParseCacheConfiguration.current == .init(
        directory: suiteCacheDirectory,
        budget: 4096,
        validation: .metadata
      ))
    }
  }
}

@Suite("Parse cache trait defaults")
struct ParseCacheTraitDefaultsTests {
  @Test("Direct trait scope restores settings after failure")
  func directScope() async throws {
    enum ScopeFailure: Error { case stopped }

    let test = try #require(Test.current)
    let trait: ParseCacheTrait = .parseCache(validation: .content)
    await #expect(throws: ScopeFailure.self) {
      try await trait.provideScope(for: test, testCase: nil) {
        #expect(ParseCacheConfiguration.current == .init(validation: .content))
        throw ScopeFailure.stopped
      }
    }
    #expect(ParseCacheConfiguration.current == nil)
  }

  @Test("Omitted directory uses environment", .parseCache(validation: .content))
  func environmentDirectory() {
    let policy = Codebase().parseCachePolicy.resolved(environment: [
      ParseCachePolicy.directoryEnvironmentKey: "/environment/cache",
      ParseCachePolicy.disableEnvironmentKey: "true",
    ])
    #expect(policy == .enabled(
      directory: URL(fileURLWithPath: "/environment/cache"),
      cachesTemporaryRoots: true,
      budget: ParseCacheConfiguration.defaultBudget,
      validation: .content
    ))
  }

  @Test("Empty trait uses cache defaults", .parseCache())
  func defaults() {
    #expect(ParseCacheConfiguration.current == .init())
  }

  @Test("Unconfigured tests keep environment policy")
  func unconfigured() {
    #expect(ParseCacheConfiguration.current == nil)
    #expect(Codebase().parseCachePolicy.resolved(environment: [
      ParseCachePolicy.disableEnvironmentKey: "true",
    ]) == .disabled)
  }

  @Test("Parallel scopes keep independent settings")
  func parallelScopes() async {
    await withTaskGroup(of: Void.self) { group in
      for budget in [1024, 2048, 4096] {
        group.addTask {
          let directory = URL(fileURLWithPath: "/cache/\(budget)")
          let configuration = ParseCacheConfiguration(
            directory: directory,
            budget: budget,
            validation: .content
          )
          await ParseCacheConfiguration.$current.withValue(configuration) {
            await Task.yield()
            #expect(ParseCacheConfiguration.current == configuration)
            #expect(Codebase().parseCachePolicy.resolved() == .enabled(
              directory: directory,
              cachesTemporaryRoots: true,
              budget: budget,
              validation: .content
            ))
          }
        }
      }
    }
    #expect(ParseCacheConfiguration.current == nil)
  }
}
