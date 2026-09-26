import BylawsCore
import BylawsPaths
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
    try await withServingState { state, clock, runs, connection, uri in
      let publicationCount = connection.publishedDiagnostics.count

      await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
      await clock.advance(by: .milliseconds(999))
      #expect(await runs.values.map(\.start) == [.zero])
      #expect(connection.publishedDiagnostics.count == publicationCount)

      await clock.advance(by: .milliseconds(2))
      await state.waitForPendingRefresh()

      let values = await runs.values
      #expect(values.count == 2)
      let refreshStart = try #require(values.last)
      #expect((Duration.seconds(1)...Duration.milliseconds(1001))
        .contains(refreshStart.start))
      #expect(refreshStart.text == "class Bad {}")
      let published = try #require(connection.publishedDiagnostics
        .last { $0.uri == uri })
      #expect(published.diagnostics.count == 1)
    }
  }

  @Test("New edit restarts delay and replaces pending text")
  func replacementDelay() async throws {
    try await withServingState { state, clock, runs, connection, uri in
      let publicationCount = connection.publishedDiagnostics.count

      await state.didChange(changeNotification(of: uri, to: "class First {}"))
      await clock.advance(by: .milliseconds(500))
      await state.didChange(changeNotification(of: uri, to: "class Latest {}"))

      await clock.advance(by: .milliseconds(500))
      #expect(await runs.values.map(\.start) == [.zero])
      await clock.advance(by: .milliseconds(499))
      #expect(await runs.values.map(\.start) == [.zero])
      #expect(connection.publishedDiagnostics.count == publicationCount)
      await clock.advance(by: .milliseconds(2))
      await state.waitForPendingRefresh()

      let values = await runs.values
      #expect(values.count == 2)
      let refreshStart = try #require(values.last)
      #expect((Duration.milliseconds(1500)...Duration.milliseconds(1501))
        .contains(refreshStart.start))
      #expect(refreshStart.text == "class Latest {}")
      let published = try #require(connection.publishedDiagnostics
        .last { $0.uri == uri })
      #expect(published.diagnostics.count == 1)
      #expect(connection.publishedDiagnostics.count == publicationCount + 1)
    }
  }

  @Test("Shutdown cancels pending refresh")
  func delayedShutdown() async throws {
    try await withServingState { state, clock, runs, connection, uri in
      let publicationCount = connection.publishedDiagnostics.count

      await state.didChange(changeNotification(of: uri, to: "class Bad {}"))
      await state.shutdown()
      await clock.advance(by: .seconds(10))

      #expect(await runs.values.map(\.start) == [.zero])
      #expect(connection.publishedDiagnostics.count == publicationCount)
    }
  }

  private func withServingState(
    _ operation: (
      BylawsLanguageServerState, TestClock<Duration>, RefreshRuns,
      TestConnection, DocumentURI
    ) async throws -> Void
  ) async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let connection = TestConnection()
    let clock = TestClock()
    let start = clock.now
    let runs = RefreshRuns()
    let sourcePath = project.source.path
    let state = await makeServingState(
      client: connection,
      project: project,
      supportsPull: false,
      clock: clock,
      refreshDelayMilliseconds: 1000,
      runner: RuleRunning(
        run: { configuration throws(CancellationError) in
          let text = configuration.overlay.text(forFileAt: sourcePath)
          await runs.record(
            RefreshRun(start: start.duration(to: clock.now), text: text)
          )
          return RuleRunResult.mock(
            rootPath: configuration.root.string,
            diagnosticAt: text == nil ? nil : sourcePath
          )
        },
        discardCaches: { _ in }
      )
    )
    await state.initialized()
    do {
      try await operation(
        state,
        clock,
        runs,
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

private struct RefreshRun: Sendable {
  let start: Duration
  let text: String?
}

private actor RefreshRuns {
  private(set) var values: [RefreshRun] = []

  func record(_ run: RefreshRun) {
    values.append(run)
  }
}
