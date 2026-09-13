import BylawsCore
import Testing

@Suite("Bounded concurrent map")
struct BoundedConcurrentMapTests {
  @Test(
    "The map preserves order at every concurrency limit",
    arguments: [0, 1, 2, 5, 100]
  )
  func preservesOrder(limit: Int) async {
    let values = await boundedConcurrentMap(
      Array(0..<12),
      maximumConcurrentTasks: limit
    ) { $0 * 2 }

    #expect(values == [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22])
  }

  @Test("The map returns nothing for no elements")
  func mapsEmptyInput() async {
    let values = await boundedConcurrentMap(
      [Int](),
      maximumConcurrentTasks: 2
    ) { $0 }

    #expect(values.isEmpty)
  }

  @available(macOS 13, iOS 16, *)
  @Test(
    "The map runs as many operations as its limit allows",
    .timeLimit(.minutes(1))
  )
  func limitsConcurrency() async {
    let check = OperationLimitCheck()
    _ = await boundedConcurrentMap(
      Array(0..<12),
      maximumConcurrentTasks: 2
    ) { value in
      await check.recordOperationStart()
      await check.recordOperationEnd()
      return value
    }

    #expect(await check.maximumNumberOfActiveOperations == 2)
  }

  @Test("The map reports an operation error")
  func reportsErrors() async {
    await #expect(throws: Failure.expected) {
      try await boundedConcurrentMap(
        Array(0..<4),
        maximumConcurrentTasks: 2
      ) { value in
        if value == 1 { throw Failure.expected }
        return value
      }
    }
  }

  private actor OperationLimitCheck {
    private var activeOperations = 0
    private var maximumActiveOperationCount = 0
    private var firstOperationContinuation: CheckedContinuation<Void, Never>?
    private var hasPausedFirstOperation = false

    func recordOperationStart() async {
      activeOperations += 1
      maximumActiveOperationCount = max(
        maximumActiveOperationCount, activeOperations
      )
      if let firstOperationContinuation {
        self.firstOperationContinuation = nil
        firstOperationContinuation.resume()
      } else if !hasPausedFirstOperation {
        hasPausedFirstOperation = true
        // withCheckedContinuation ignores cancellation, so the time limit
        // needs the handler to release the wait.
        await withTaskCancellationHandler {
          await withCheckedContinuation { firstOperationContinuation = $0 }
        } onCancel: {
          Task { @concurrent in await self.releaseFirstOperation() }
        }
      }
    }

    func recordOperationEnd() {
      activeOperations -= 1
    }

    var maximumNumberOfActiveOperations: Int {
      maximumActiveOperationCount
    }

    private func releaseFirstOperation() {
      firstOperationContinuation?.resume()
      firstOperationContinuation = nil
    }
  }

  private enum Failure: Error {
    case expected
  }
}
