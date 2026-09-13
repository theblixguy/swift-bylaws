import BylawsRunner
import Clocks
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("LSP refresh scheduling", .timeLimit(.minutes(3)))
struct RefreshSchedulingTests {
  @Test("Refresh runs after configured delay")
  func refreshDeadline() async throws {
    try await withServingState { state, clock, starts, connection, uri in
      let publicationCount = connection.publishedDiagnostics.count

      await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
      await clock.advance(by: .milliseconds(999))
      #expect(await starts.values == [.zero])
      #expect(connection.publishedDiagnostics.count == publicationCount)

      await clock.advance(by: .milliseconds(2))
      await state.waitForPendingRefresh()

      let values = await starts.values
      #expect(values.count == 2)
      let refreshStart = try #require(values.last)
      #expect((Duration.seconds(1)...Duration.milliseconds(1001))
        .contains(refreshStart))
      let published = try #require(connection.publishedDiagnostics
        .last { $0.uri == uri })
      #expect(published.diagnostics.count == 1)
    }
  }

  @Test("New edit restarts delay and replaces pending text")
  func replacementDelay() async throws {
    try await withServingState { state, clock, starts, connection, uri in
      let publicationCount = connection.publishedDiagnostics.count

      await state.didChange(changeNotification(of: uri, to: "class First {}"))
      await clock.advance(by: .milliseconds(500))
      await state.didChange(changeNotification(of: uri, to: "class Latest {}"))

      await clock.advance(by: .milliseconds(500))
      #expect(await starts.values == [.zero])
      await clock.advance(by: .milliseconds(499))
      #expect(await starts.values == [.zero])
      #expect(connection.publishedDiagnostics.count == publicationCount)
      await clock.advance(by: .milliseconds(2))
      await state.waitForPendingRefresh()

      let values = await starts.values
      #expect(values.count == 2)
      let refreshStart = try #require(values.last)
      #expect((Duration.milliseconds(1500)...Duration.milliseconds(1501))
        .contains(refreshStart))
      let published = try #require(connection.publishedDiagnostics
        .last { $0.uri == uri })
      #expect(published.diagnostics
        .map(\.message) == ["Latest violates 'Classes are final'"])
      #expect(connection.publishedDiagnostics.count == publicationCount + 1)
    }
  }

  @Test("Shutdown cancels pending refresh")
  func delayedShutdown() async throws {
    try await withServingState { state, clock, starts, connection, uri in
      let publicationCount = connection.publishedDiagnostics.count

      await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
      await state.shutdown()
      await clock.advance(by: .seconds(10))

      #expect(await starts.values == [.zero])
      #expect(connection.publishedDiagnostics.count == publicationCount)
    }
  }

  private func withServingState(
    _ operation: (
      BylawsLanguageServerState, TestClock<Duration>, RefreshStarts,
      TestConnection, DocumentURI
    ) async throws -> Void
  ) async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let connection = TestConnection()
    let clock = TestClock()
    let start = clock.now
    let starts = RefreshStarts()
    let state = await makeServingState(
      client: connection,
      project: project,
      supportsPull: false,
      clock: clock,
      refreshDelayMilliseconds: 1000,
      runner: RuleRunning(
        run: { configuration throws(CancellationError) in
          await starts.record(start.duration(to: clock.now))
          return try await RuleRunner.run(configuration)
        },
        discardCaches: RuleRunner.discardCaches(under:)
      )
    )
    await state.initialized()
    do {
      try await operation(
        state,
        clock,
        starts,
        connection,
        DocumentURI(project.source)
      )
    } catch {
      await state.shutdown()
      throw error
    }
    await state.shutdown()
  }
}

private actor RefreshStarts {
  private(set) var values: [Duration] = []

  func record(_ start: Duration) {
    values.append(start)
  }
}
