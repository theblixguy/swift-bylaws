import Foundation

package func boundedConcurrentMap<
  Element: Sendable, Value: Sendable, Failure: Error
>(
  _ elements: [Element],
  maximumConcurrentTasks: Int,
  operation: @escaping @Sendable (Element) async throws(Failure) -> Value
) async throws(Failure) -> [Value] {
  guard !elements.isEmpty else { return [] }
  let concurrencyLimit = min(max(1, maximumConcurrentTasks), elements.count)

  let outcome = await withTaskGroup(
    of: (index: Int, result: Result<Value, Failure>).self,
    returning: Result<[Value], Failure>.self
  ) { group in
    var nextIndex = 0
    for index in 0..<concurrencyLimit {
      group.addTask {
        (index, await Result(catching: { () async throws(Failure) in
          try await operation(elements[index])
        }))
      }
      nextIndex += 1
    }

    var ordered = [Value?](repeating: nil, count: elements.count)
    for await completed in group {
      switch completed.result {
      case let .success(value):
        ordered[completed.index] = value
      case let .failure(failure):
        group.cancelAll()
        return .failure(failure)
      }
      if nextIndex < elements.count {
        let index = nextIndex
        group.addTask {
          (index, await Result(catching: { () async throws(Failure) in
            try await operation(elements[index])
          }))
        }
        nextIndex += 1
      }
    }

    return .success(ordered.map { value in
      guard let value else {
        preconditionFailure(
          "The task group completed before producing all results"
        )
      }
      return value
    })
  }
  return try outcome.get()
}
