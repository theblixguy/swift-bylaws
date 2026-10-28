#if os(macOS) || os(Linux)
  import BylawsTestSupport
  import Testing

  @Suite("Process test concurrency", .timeLimit(.minutes(1)))
  struct ProcessTestLimitTests {
    @Test("Scopes run up to concurrency limit")
    func boundedScopes() async throws {
      let limit = ProcessTestLimit(maximumConcurrentScopes: 2)
      let control = ScopeControl()
      try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<12 {
          group.addTask {
            try await limit.withScope {
              await control.enter()
              await control.leave()
            }
          }
        }
        try await group.waitForAll()
      }
      #expect(await control.completed == 12)
      #expect(await control.maximumActive == 2)
    }

    @Test("Thrown scope releases capacity")
    func failedScope() async throws {
      let limit = ProcessTestLimit(maximumConcurrentScopes: 1)
      await #expect(throws: MockError.failed) {
        try await limit.withScope { throw MockError.failed }
      }
      try await confirmation("Later scope runs") { entered in
        try await limit.withScope { entered() }
      }
    }

    @Test("Cancelled caller skips scope body")
    func cancelledCaller() async throws {
      let limit = ProcessTestLimit(maximumConcurrentScopes: 1)
      await withTaskGroup(of: Void.self) { group in
        group.cancelAll()
        group.addTask {
          await #expect(throws: CancellationError.self) {
            try await limit.withScope { Issue.record("Scope body ran") }
          }
        }
      }
      try await confirmation("Later scope runs") { entered in
        try await limit.withScope { entered() }
      }
    }

    @Test("Cancelled scope releases capacity")
    func cancelledScope() async throws {
      let limit = ProcessTestLimit(maximumConcurrentScopes: 1)
      let control = HeldScope()
      let task = Task { @concurrent in
        try await limit.withScope { try await control.wait() }
      }
      await control.waitUntilEntered()
      task.cancel()
      await #expect(throws: CancellationError.self) { try await task.value }
      try await confirmation("Later scope runs") { entered in
        try await limit.withScope { entered() }
      }
    }

    @Test("Cancelled waiting caller returns before held scope completes")
    func cancelledWaitingScope() async throws {
      let queued = AsyncStream<Void>.makeStream()
      let limit = ProcessTestLimit(maximumConcurrentScopes: 1) {
        _ = queued.continuation.yield(())
      }
      let control = HeldScope()
      let holder = Task { @concurrent in
        try await limit.withScope { try await control.wait() }
      }
      await control.waitUntilEntered()
      let waiting = Task { @concurrent in
        try await limit.withScope { Issue.record("Cancelled scope body ran") }
      }
      defer {
        holder.cancel()
        waiting.cancel()
        queued.continuation.finish()
      }
      _ = try #require(await queued.stream.first { _ in true })
      waiting.cancel()
      await #expect(throws: CancellationError.self) { try await waiting.value }
      await control.release()
      try await holder.value
      try await confirmation("Later scope runs") { entered in
        try await limit.withScope { entered() }
      }
    }

    private actor ScopeControl {
      private var active = 0
      private var first: CheckedContinuation<Void, Never>?
      private var hasPaused = false
      private(set) var maximumActive = 0
      private(set) var completed = 0

      func enter() async {
        active += 1
        maximumActive = max(maximumActive, active)
        if let first {
          self.first = nil
          first.resume()
        } else if !hasPaused {
          hasPaused = true
          await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
              if Task.isCancelled {
                continuation.resume()
              } else {
                first = continuation
              }
            }
          } onCancel: {
            Task { @concurrent in await self.release() }
          }
        }
      }

      func leave() {
        active -= 1
        completed += 1
      }

      private func release() {
        first?.resume()
        first = nil
      }
    }

    private actor HeldScope {
      private let completion: AsyncStream<Void>.Continuation
      private let completions: AsyncStream<Void>
      private var entered = false
      private var start: CheckedContinuation<Void, Never>?

      init() {
        (completions, completion) = AsyncStream.makeStream()
      }

      func wait() async throws {
        entered = true
        start?.resume()
        start = nil
        _ = await completions.first { _ in true }
        try Task.checkCancellation()
      }

      func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { start = $0 }
      }

      func release() {
        completion.yield(())
        completion.finish()
      }
    }

    private enum MockError: Error {
      case failed
    }
  }
#endif
