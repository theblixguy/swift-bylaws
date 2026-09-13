import Clocks
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

func makeServingState(
  client: TestConnection = TestConnection(),
  project: DiagnosticTestProject,
  supportsPull: Bool,
  clock: any Clock<Duration> = UnimplementedClock(),
  refreshDelayMilliseconds: Int = 0,
  runner: RuleRunning = .standard
) async -> BylawsLanguageServerState {
  let state = BylawsLanguageServerState(
    clock: clock,
    client: client,
    runner: runner
  )
  var request = initializeRequest(
    root: project.root,
    supportsPull: supportsPull
  )
  request.initializationOptions = .dictionary([
    "refreshDelayMilliseconds": .int(refreshDelayMilliseconds),
  ])
  _ = await state.initialize(request)
  return state
}

func diagnosticItems(
  from state: BylawsLanguageServerState,
  for uri: DocumentURI
) async throws -> [LanguageServerProtocol.Diagnostic] {
  let report = await state.diagnostics(
    for: DocumentDiagnosticsRequest(
      textDocument: TextDocumentIdentifier(uri)
    )
  )
  guard case let .full(fullReport) = report else {
    Issue.record("Expected a full diagnostic report")
    return []
  }
  return fullReport.items
}

func changeNotification(
  of uri: DocumentURI,
  to text: String
) -> DidChangeTextDocumentNotification {
  DidChangeTextDocumentNotification(
    textDocument: VersionedTextDocumentIdentifier(uri, version: 1),
    contentChanges: [TextDocumentContentChangeEvent(text: text)]
  )
}

func initializeRequest(
  root: URL,
  supportsPull: Bool
) -> InitializeRequest {
  let textDocument = if supportsPull {
    TextDocumentClientCapabilities(diagnostic: .init())
  } else {
    TextDocumentClientCapabilities()
  }
  return InitializeRequest(
    rootURI: DocumentURI(root),
    capabilities: ClientCapabilities(textDocument: textDocument),
    workspaceFolders: nil
  )
}

func saveNotification(
  for uri: DocumentURI
) -> DidSaveTextDocumentNotification {
  DidSaveTextDocumentNotification(
    textDocument: TextDocumentIdentifier(uri)
  )
}
