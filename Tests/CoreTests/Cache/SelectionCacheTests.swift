import BylawsSemantics
import Foundation
import Testing
@testable import BylawsCore

@Suite("Shared query selections", .timeLimit(.minutes(1)))
struct SelectionCacheTests {
  @Test("Zero budget disables an inherited cache within its scope")
  func nestedDisabledScope() async throws {
    try await SelectionCache.withBudget {
      let outer = try #require(SelectionCache.current)
      await SelectionCache.withBudget(0) {
        #expect(SelectionCache.current == nil)
      }
      #expect(SelectionCache.current === outer)
    }
    #expect(SelectionCache.current == nil)
  }

  @Test("Repeated plans share completed storage")
  func repeatedPlan() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    let filters: [NameFilter] = [.prefixed(["Order"]), .suffixed(["View"])]
    _ = try await cache.selection(from: source, filters: filters)
    let first = try await cache.selection(from: source, filters: filters)
    let second = try await cache.selection(from: source, filters: filters)

    #expect(first.storage === second.storage)
    #expect(second.map(\.name) == ["OrderView"])
    #expect(await cache.retainedBytes <= 1_000_000)
  }

  @Test("One-off broad plans retain keys without result arrays")
  func oneOffPlans() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 32768)
    for index in 0..<100 {
      let result = try await cache.selection(
        from: source, filters: [.excluding(["Missing\(index)"])]
      )
      #expect(result.count == source.count)
    }
    #expect(await cache.retainedBytes <= 32768 / 16)
  }

  @Test(
    "Zero and small budgets preserve results",
    arguments: [UInt(0), 100, 1000]
  )
  func smallBudget(budget: UInt) async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: budget)
    for _ in 0..<3 {
      let result = try await cache.selection(
        from: source,
        filters: [.prefixed(["Order"])]
      )
      #expect(result.map(\.name) == ["OrderView", "OrderModel"])
      #expect(await cache.retainedBytes <= budget)
    }
  }

  @Test("Different snapshots keep separate results")
  func snapshots() async throws {
    let first = await classes(in: codebase)
    let other = try Self.parse("class Other {}", path: "/Other.swift")
    let second = await classes(in: other)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    for _ in 0..<3 {
      let left = try await cache.selection(
        from: first,
        filters: [.excluding([])]
      )
      let right = try await cache.selection(
        from: second,
        filters: [.excluding([])]
      )
      #expect(left.count == 3)
      #expect(right.map(\.name) == ["Other"])
    }
  }

  @Test("Concurrent callers share one calculation")
  func sameKey() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    let control = BuildControl()
    let key = SelectionCacheStore.Key(
      source: source.storage.identity,
      filters: []
    )
    _ = try await cache.value(from: source.storage, for: key) { source }
    let first = Task { @concurrent in
      try await cache.value(from: source.storage, for: key) {
        await control.wait()
        return source
      }
    }
    await control.waitUntilStarted()
    async let second: Selection<Class> = cache.value(
      from: source.storage,
      for: key
    ) {
      Issue.record("A matching query must share the active calculation")
      return source
    }
    await control.resume()

    let results = try await (first.value, second)
    #expect(results.0.storage === results.1.storage)
  }

  @Test("Different keys run while another calculation waits")
  func differentKeys() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    let control = BuildControl()
    let first = Task { @concurrent in
      try await cache.value(
        from: source.storage,
        for: .init(source: UUID(), filters: [])
      ) {
        await control.wait()
        return source
      }
    }
    await control.waitUntilStarted()
    let other = try await cache.value(
      from: source.storage,
      for: .init(source: UUID(), filters: [])
    ) {
      source
    }
    #expect(other.count == 3)
    await control.resume()
    _ = try await first.value
  }

  @Test("Cancelled callers leave shared work available")
  func cancellation() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    let control = BuildControl()
    let key = SelectionCacheStore.Key(
      source: source.storage.identity,
      filters: []
    )
    _ = try await cache.value(from: source.storage, for: key) { source }
    let first = Task { @concurrent in
      try await cache.value(from: source.storage, for: key) {
        await control.wait()
        return source
      }
    }
    await control.waitUntilStarted()
    first.cancel()
    await control.resume()
    await #expect(throws: CancellationError.self) { try await first.value }
    let result = try await cache.value(from: source.storage, for: key) {
      source
    }
    #expect(result.count == 3)
  }

  @Test("Scope completion releases results and prevents later retention")
  func completion() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    for _ in 0..<3 {
      _ = try await cache.selection(from: source, filters: [.excluding([])])
    }
    #expect(await cache.retainedBytes > 0)
    await cache.finish()
    for _ in 0..<3 {
      _ = try await cache.selection(from: source, filters: [.excluding([])])
    }
    #expect(await cache.retainedBytes == 0)
  }

  @Test("Shared prefixes keep declaration order for different queries")
  func sharedPrefix() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    let prefix: [NameFilter] = [.prefixed(["Order"])]
    _ = try await cache.selection(
      from: source,
      filters: prefix + [.suffixed(["View"])]
    )
    _ = try await cache.selection(
      from: source,
      filters: prefix + [.suffixed(["Model"])]
    )
    let stored = try await cache.selection(from: source, filters: prefix)
    let again = try await cache.selection(from: source, filters: prefix)

    #expect(stored.storage === again.storage)
    #expect(again.map(\.name) == ["OrderView", "OrderModel"])
  }

  @Test("Oversized results reach callers without retention")
  func oversizedResult() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1)
    let key = SelectionCacheStore.Key(
      source: source.storage.identity,
      filters: []
    )
    let first = try await cache.value(from: source.storage, for: key) { source }
    let second = try await cache
      .value(from: source.storage, for: key) { source.excluding("OrderView") }

    #expect(first.count == 3)
    #expect(second.count == 2)
    #expect(await cache.retainedBytes == 0)
  }

  @Test("Failed calculations can be retried")
  func retry() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    let key = SelectionCacheStore.Key(
      source: source.storage.identity,
      filters: []
    )
    await #expect(throws: CancellationError.self) {
      try await cache
        .value(
          from: source.storage,
          for: key
        ) { () throws -> Selection<Class> in
          throw CancellationError()
        }
    }
    let result = try await cache
      .value(from: source.storage, for: key) { source }
    #expect(result.count == 3)
  }

  @Test("Inspection keeps all steps when selections are cached")
  func inspection() async throws {
    let app = codebase
    let rule = Rule("views", "Views are final") {
      let source = await classes(in: app)
      let filters: [NameFilter] = [.prefixed(["Order"]), .suffixed(["View"])]
      let result: Selection<Class> = if let cache = SelectionCache.current {
        try await cache.selection(from: source, filters: filters)
      } else {
        source.filtering(filters)
      }
      return Violations(of: .isFinal, in: result)
    }
    let expected = try await rule.inspect()
    #expect(expected.selections.count == 2)
    let actual = try await SelectionCache.withBudget {
      _ = try await rule.findings()
      _ = try await rule.findings()
      return try await rule.inspect()
    }
    #expect(actual.selections == expected.selections)
    #expect(actual.findings.violations == expected.findings.violations)
  }

  @Test("Budget pressure releases least recently used results")
  func eviction() async throws {
    let app = try Self.parse(
      (0..<100).map { "class Type\($0) {}" }.joined(separator: "\n")
    )
    let source = await classes(in: app)
    let measure = SelectionCacheStore(maximumBytes: 1_000_000)
    let filtersA: [NameFilter] = [.excluding(["A"])]
    let filtersB: [NameFilter] = [.excluding(["B"])]
    let filtersC: [NameFilter] = [.excluding(["C"])]
    for _ in 0..<2 {
      _ = try await measure.selection(
        from: source,
        filters: filtersA
      )
    }
    for _ in 0..<2 {
      _ = try await measure.selection(from: source, filters: filtersB)
    }
    let bytes = await measure.retainedBytes
    let cache = SelectionCacheStore(maximumBytes: UInt(bytes))
    for _ in 0..<2 {
      _ = try await cache.selection(
        from: source,
        filters: filtersA
      )
    }
    for _ in 0..<2 {
      _ = try await cache.selection(
        from: source,
        filters: filtersB
      )
    }
    let previousB = try await cache.selection(from: source, filters: filtersB)
    let recentA = try await cache.selection(from: source, filters: filtersA)
    for _ in 0..<2 {
      _ = try await cache.selection(
        from: source,
        filters: filtersC
      )
    }
    let retainedA = try await cache.selection(from: source, filters: filtersA)
    let rebuiltB = try await cache.selection(from: source, filters: filtersB)

    #expect(recentA.storage === retainedA.storage)
    #expect(previousB.storage !== rebuiltB.storage)
    #expect(await cache.retainedBytes <= bytes)
  }

  @Test("Shared source projection is charged once")
  func sharedProjectionBudget() async throws {
    let source = await classes(in: codebase)
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    for _ in 0..<2 {
      _ = try await cache.selection(from: source, filters: [.excluding(["A"])])
    }
    let first = await cache.retainedBytes
    for _ in 0..<2 {
      _ = try await cache.selection(from: source, filters: [.excluding(["B"])])
    }
    let second = await cache.retainedBytes

    #expect(second > first)
    #expect(second - first < first)
    #expect(second <= 1_000_000)
  }

  @Test("Cached selections keep source projection until scope ends")
  func projectionLifetime() async throws {
    let cache = SelectionCacheStore(maximumBytes: 1_000_000)
    func populate() async throws -> WeakProjection {
      let source = await classes(in: codebase)
      for _ in 0..<2 {
        _ = try await cache.selection(
          from: source,
          filters: [.prefixed(["Order"])]
        )
      }
      return WeakProjection(value: source.storage)
    }

    let projection = try await populate()
    #expect(projection.value != nil)
    await cache.finish()
    #expect(projection.value == nil)
    #expect(await cache.retainedBytes == 0)
  }

  @Test("Evicting the last selection releases its source projection")
  func evictedProjection() async throws {
    let contents = (0..<100).map { "class Type\($0) {}" }
      .joined(separator: "\n")
    let app = try Self.parse(contents)
    func populate(
      _ cache: SelectionCacheStore,
      from app: ParsedCodebase
    ) async throws -> WeakProjection {
      let source = await classes(in: app)
      for _ in 0..<2 {
        _ = try await cache.selection(
          from: source,
          filters: [.excluding(["Missing"])]
        )
      }
      return WeakProjection(value: source.storage)
    }

    let measure = SelectionCacheStore(maximumBytes: 1_000_000)
    _ = try await populate(measure, from: app)
    let budget = await measure.retainedBytes
    await measure.finish()
    let cache = SelectionCacheStore(maximumBytes: UInt(budget))
    let first = try await populate(cache, from: app)
    #expect(first.value != nil)

    let other = try Self.parse(contents, path: "/Other.swift")
    let second = try await populate(cache, from: other)
    #expect(first.value == nil)
    #expect(second.value != nil)
    #expect(await cache.retainedBytes <= budget)
  }

  private struct WeakProjection {
    weak var value: SelectionStorage<Class>?
  }

  private let codebase: ParsedCodebase

  init() throws {
    codebase = try Self.parse(
      "class OrderView {}\nclass OrderModel {}\nclass Other {}"
    )
  }

  private static func parse(
    _ source: String,
    path: String = "/App.swift"
  ) throws -> ParsedCodebase {
    let file = try FileCollector.collect(source: source, path: path)
    return ParsedCodebase(rootPath: "/", files: [file])
  }

  private func classes(in codebase: ParsedCodebase) async -> Selection<Class> {
    let storage = await codebase.projection(for: .classes) {
      $0.flatMap(\.classes)
    }
    return Selection(
      storage: storage,
      queryDescription: "classes",
      rootPath: codebase.rootPath
    )
  }

  private actor BuildControl {
    private var completion: CheckedContinuation<Void, Never>?
    private var start: CheckedContinuation<Void, Never>?

    func wait() async {
      await withCheckedContinuation { continuation in
        completion = continuation
        start?.resume()
        start = nil
      }
    }

    func waitUntilStarted() async {
      guard completion == nil else { return }
      await withCheckedContinuation { start = $0 }
    }

    func resume() {
      completion?.resume()
      completion = nil
    }
  }
}
