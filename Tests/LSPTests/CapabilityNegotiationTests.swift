import Clocks
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("LSP capability negotiation")
struct CapabilityNegotiationTests {
  @Test("Editor pull support enables diagnostic provider")
  func pullSupport() async {
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    let result = await state.initialize(
      request(
        textDocument: TextDocumentClientCapabilities(
          diagnostic: .init()
        )
      )
    )

    #expect(result.capabilities.diagnosticProvider != nil)
  }

  @Test("Missing editor pull support leaves diagnostic provider nil")
  func missingPullSupport() async {
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    let result = await state.initialize(request(textDocument: nil))

    #expect(result.capabilities.diagnosticProvider == nil)
  }

  private func request(
    textDocument: TextDocumentClientCapabilities?
  ) -> InitializeRequest {
    InitializeRequest(
      rootURI: DocumentURI(
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      ),
      capabilities: ClientCapabilities(textDocument: textDocument),
      workspaceFolders: nil
    )
  }
}
