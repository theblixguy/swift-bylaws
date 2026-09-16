import Bylaws
import BylawsCore
import Testing

@Suite("Selection-cache trait", .selectionCache(budget: 4096))
struct SelectionCacheTraitTests {
  @Test("Suite shares cache across parameterised cases", arguments: [0, 1])
  func sharedCache(_: Int) async throws {
    try await Self.scopes.check(.suite)
  }

  @Test("Test overrides suite cache", .selectionCache(budget: 1024))
  func testOverride() async throws {
    try await Self.scopes.check(.test)
  }

  @Test(
    "Test shares cache across cases after argument evaluation",
    .selectionCache(budget: 2048),
    arguments: [SelectionCache.current, SelectionCache.current]
  )
  func parameterisedCache(argumentCache: SelectionCacheStore?) async throws {
    #expect(argumentCache == nil)
    try await Self.scopes.check(.parameterisedTest)
  }

  @Test("Zero budget disables inherited cache", .selectionCache(budget: 0))
  func disabledTest() {
    #expect(SelectionCache.current == nil)
  }

  @Test("Omitted budget uses default")
  func defaultBudget() {
    let trait: SelectionCacheTrait = .selectionCache()
    #expect(trait.budget == SelectionCache.defaultBudget)
  }

  @Test("Throwing scope restores enclosing cache")
  func throwingScope() async throws {
    let parent = try #require(SelectionCache.current)
    let test = try #require(Test.current)
    let trait: SelectionCacheTrait = .selectionCache(budget: 2048)

    await #expect(throws: MockError.failed) {
      try await trait.provideScope(for: test, testCase: nil) {
        let child = try #require(SelectionCache.current)
        #expect(child !== parent)
        throw MockError.failed
      }
    }

    #expect(SelectionCache.current === parent)
  }

  @Suite("Inherited suite cache")
  struct Inherited {
    @Test("Nested suite shares enclosing cache")
    func inheritedCache() async throws {
      try await SelectionCacheTraitTests.scopes.check(.suite)
    }
  }

  @Suite("Overridden suite cache", .selectionCache(budget: 8192))
  struct Overridden {
    @Test("Nested suite shares its own cache", arguments: [0, 1])
    func overriddenCache(_: Int) async throws {
      try await SelectionCacheTraitTests.scopes.check(.nestedSuite)
    }
  }

  @Suite("Disabled suite cache", .selectionCache(budget: 0))
  struct Disabled {
    @Test("Nested suite disables enclosing cache")
    func disabledCache() {
      #expect(SelectionCache.current == nil)
    }

    @Test("Test can enable cache within disabled suite", .selectionCache())
    func enabledTest() async throws {
      try await SelectionCacheTraitTests.scopes.check(.enabledTest)
    }
  }

  private static let scopes = CacheScopes()

  private enum MockError: Error {
    case failed
  }

  private actor CacheScopes {
    enum Group: Hashable {
      case suite, test, parameterisedTest, nestedSuite, enabledTest
    }

    private var caches: [Group: SelectionCacheStore] = [:]

    func check(
      _ group: Group,
      sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
      let current = try #require(
        SelectionCache.current,
        sourceLocation: sourceLocation
      )
      for (existingGroup, existingCache) in caches {
        #expect(
          (current === existingCache) == (group == existingGroup),
          sourceLocation: sourceLocation
        )
      }
      caches[group] = current
    }
  }
}
