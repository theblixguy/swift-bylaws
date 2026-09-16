import BylawsCore
import BylawsPaths
import BylawsRunner
import Clocks
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("LSP diagnostic requests")
struct DiagnosticRequestTests {
  @Test(
    "Queued diagnostic requests use editor text without delay",
    .timeLimit(.minutes(3))
  )
  func queuedPullRequests() async throws {
    let project = try DiagnosticTestProject(source: "final class Good {}")
    let clock = TestClock()
    let start = clock.now
    let sourcePath = project.source.path
    let server = BylawsLanguageServer(
      client: TestConnection(),
      clock: clock,
      runner: RuleRunning(
        run: { configuration throws(CancellationError) in
          let diagnosticPath =
            configuration.overlay.text(forFileAt: sourcePath) == "class Bad {}"
              ? sourcePath
              : nil
          return RuleRunResult.mock(
            rootPath: configuration.root.string,
            diagnosticAt: diagnosticPath
          )
        },
        discardCaches: { _ in }
      ),
      onExit: { _ in }
    )
    var initialization = initializeRequest(
      root: project.root,
      supportsPull: true
    )
    initialization.initializationOptions = .dictionary([
      "refreshDelayMilliseconds": .int(3_600_000),
    ])
    _ = try await response(to: initialization, id: 1, from: server)
    server.handle(InitializedNotification())
    let uri = DocumentURI(project.source)
    let request =
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    let saved = try await response(to: request, id: 2, from: server)
    guard case let .full(saved) = saved else {
      Issue.record("The server must return a full report")
      return
    }
    #expect(saved.items.isEmpty)

    server
      .handle(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
        uri: uri,
        language: .swift,
        version: 1,
        text: "class Bad {}"
      )))
    let opened = try await response(to: request, id: 3, from: server)
    guard case let .full(opened) = opened else {
      Issue.record("The server must return a full report")
      return
    }
    #expect(opened.items.count == 1)

    server.handle(changeNotification(of: uri, to: "final class Good {}"))
    let changed = try await response(to: request, id: 4, from: server)
    guard case let .full(changed) = changed else {
      Issue.record("The server must return a full report")
      return
    }
    #expect(changed.items.isEmpty)
    #expect(changed.resultId != opened.resultId)
    _ = try await response(to: ShutdownRequest(), id: 5, from: server)
    #expect(clock.now == start)
    try await clock.checkSuspension()
  }

  private func response<Request: RequestType>(
    to request: Request,
    id: Int,
    from server: BylawsLanguageServer
  ) async throws -> Request.Response {
    let (responses, continuation) = AsyncStream<LSPResult<Request.Response>>
      .makeStream(bufferingPolicy: .bufferingNewest(1))
    server.handle(request, id: .number(id)) { result in
      continuation.yield(result)
      continuation.finish()
    }
    var iterator = responses.makeAsyncIterator()
    guard let result = await iterator.next() else { throw CancellationError() }
    return try result.get()
  }
}
