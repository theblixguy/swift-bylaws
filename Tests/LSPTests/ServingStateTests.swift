import Clocks
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("LSP serving state")
struct ServingStateTests {
  @Test("Server waits for initialisation before serving requests")
  func beforeInitialize() async {
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )

    #expect(await state.isServing == false)
    #expect(await state.canExitSuccessfully == false)
  }

  @Test("Initialisation enables request handling")
  func afterInitialize() async {
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    _ = await state.initialize(Self.request)

    #expect(await state.isServing)
  }

  @Test("Shutdown ends request handling and permits successful exit")
  func afterShutdown() async {
    let state = BylawsLanguageServerState(
      clock: UnimplementedClock(),
      client: TestConnection()
    )
    _ = await state.initialize(Self.request)
    await state.shutdown()

    #expect(await state.isServing == false)
    #expect(await state.canExitSuccessfully)
  }

  private static var request: InitializeRequest {
    InitializeRequest(
      rootURI: DocumentURI(
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      ),
      capabilities: ClientCapabilities(),
      workspaceFolders: nil
    )
  }
}
