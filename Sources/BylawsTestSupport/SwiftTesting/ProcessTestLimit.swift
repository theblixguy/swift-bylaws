#if os(macOS) || os(Linux)
  import Foundation

  package actor ProcessTestLimit {
    static let shared = ProcessTestLimit(maximumConcurrentScopes: 2)

    private struct Waiter {
      let id: UUID
      let continuation: CheckedContinuation<Void, any Error>
    }

    private var available: Int
    private var waiters: [Waiter] = []
    private let onQueued: @Sendable () -> Void

    package init(
      maximumConcurrentScopes: Int,
      onQueued: @escaping @Sendable () -> Void = {}
    ) {
      available = max(1, maximumConcurrentScopes)
      self.onQueued = onQueued
    }

    package func withScope(
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      try await acquire()
      defer { release() }
      try Task.checkCancellation()
      try await function()
    }

    private func acquire() async throws {
      try Task.checkCancellation()
      if available > 0 {
        available -= 1
        return
      }
      let id = UUID()
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
          } else {
            waiters.append(Waiter(id: id, continuation: continuation))
            onQueued()
          }
        }
      } onCancel: {
        Task { @concurrent in await self.cancel(id) }
      }
    }

    private func release() {
      if waiters.isEmpty {
        available += 1
      } else {
        waiters.removeFirst().continuation.resume()
      }
    }

    private func cancel(_ id: UUID) {
      guard let index = waiters.firstIndex(where: { $0.id == id }) else {
        return
      }
      waiters.remove(at: index).continuation.resume(
        throwing: CancellationError()
      )
    }
  }
#endif
