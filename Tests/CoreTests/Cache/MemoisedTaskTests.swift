import BylawsCore
import Testing

@Suite("Memoised task completion", .timeLimit(.minutes(1)))
struct MemoisedTaskTests {
  @Test("Removed task returns value and leaves cache empty")
  func removedTask() async {
    let cache = MockCache()
    let control = BuildControl()
    let first = Task { @concurrent in
      await cache.value {
        await control.wait()
        return "First"
      }
    }
    await control.waitUntilStarted()
    await cache.remove()

    await control.resume()
    #expect(await first.value == "First")
    #expect(await cache.storedValue == nil)
  }

  @Test("Older task keeps replacement value in cache")
  func replacedTask() async {
    let cache = MockCache()
    let control = BuildControl()
    let first = Task { @concurrent in
      await cache.value {
        await control.wait()
        return "First"
      }
    }
    await control.waitUntilStarted()
    await cache.remove()
    #expect(await cache.value { "Second" } == "Second")

    await control.resume()
    #expect(await first.value == "First")
    #expect(await cache.storedValue == "Second")
  }

  private actor MockCache {
    private var entry: MemoisedTask<String, Never>?
    private(set) var storedValue: String?

    func value(build: @escaping @Sendable () async -> String) async -> String {
      await MemoisedTask.value(
        name: "Test cache",
        lookup: { entry },
        insert: { entry = $0 },
        remove: { entry = nil },
        storeValue: { storedValue = $0 },
        build: build
      )
    }

    func remove() {
      entry = nil
      storedValue = nil
    }
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
