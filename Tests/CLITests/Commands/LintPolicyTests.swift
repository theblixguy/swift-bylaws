import BylawsInterpreter
import BylawsPaths
import Foundation
import Testing
@testable import bylaws_cli
@testable import BylawsRunner

@Suite("Lint command policy")
struct LintPolicyTests {
  @Test("A cancelled rule run throws CancellationError")
  func cancelledRun() async {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let task = Task { @concurrent in
      for await _ in stream { break }
      return try await RuleRunner.run(
        RuleRunConfiguration(root: .currentDirectory)
      )
    }

    task.cancel()
    continuation.yield(())
    continuation.finish()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test("An unknown --only rule ID is a load error")
  func unknownOnlyID() {
    let selection = RuleSelector.select(
      from: [],
      only: ["does-not-exist"],
      skip: [],
      defaultLocation: rulesFileLocation()
    )

    #expect(selection.rules.isEmpty)
    #expect(selection.diagnostics.count == 1)
    #expect(
      selection.diagnostics.first?.message
        == "rule ID 'does-not-exist' does not exist"
    )
  }

  @Test("An unknown --skip rule ID is a load error")
  func unknownSkipID() {
    let selection = RuleSelector.select(
      from: [],
      only: [],
      skip: ["does-not-exist"],
      defaultLocation: rulesFileLocation()
    )

    #expect(selection.rules.isEmpty)
    #expect(selection.diagnostics.count == 1)
    #expect(
      selection.diagnostics.first?.message
        == "rule ID 'does-not-exist' does not exist"
    )
  }
}
