package import LanguageServerProtocol
import ToolsProtocolsSwiftExtensions

package final class BylawsLanguageServer: MessageHandler {
  private let onExit: @Sendable (Bool) -> Void
  private let messageQueue = AsyncQueue<Serial>()
  private let state: BylawsLanguageServerState

  package init(
    client: any Connection,
    clock: any Clock<Duration> = ContinuousClock(),
    onExit: @Sendable @escaping (Bool) -> Void
  ) {
    state = BylawsLanguageServerState(clock: clock, client: client)
    self.onExit = onExit
  }

  package func handle(_ notification: some NotificationType) {
    messageQueue.async { [self] in
      switch notification {
      case is InitializedNotification:
        await state.initialized()
      case let notification as DidOpenTextDocumentNotification:
        await state.didOpen(notification)
      case let notification as DidChangeTextDocumentNotification:
        await state.didChange(notification)
      case let notification as DidSaveTextDocumentNotification:
        await state.didSave(notification)
      case let notification as DidCloseTextDocumentNotification:
        await state.didClose(notification)
      case is ExitNotification:
        onExit(await state.canExitSuccessfully)
      default:
        break
      }
    }
  }

  package func handle<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
  ) {
    messageQueue.async { [self] in
      switch request {
      case let request as InitializeRequest:
        let response = await state.initialize(request)
        sendResponse(response, using: reply)
      case is ShutdownRequest:
        await state.shutdown()
        sendResponse(ShutdownRequest.Response(), using: reply)
      default:
        guard await state.isServing else {
          reply(.failure(ResponseError(
            code: .serverNotInitialized,
            message: "the server is not serving requests"
          )))
          return
        }
        switch request {
        case let request as DocumentDiagnosticsRequest:
          let response = await state.diagnostics(for: request)
          sendResponse(response, using: reply)
        default:
          reply(.failure(.requestNotImplemented(Request.self)))
        }
      }
    }
  }

  private func sendResponse<Expected>(
    _ response: Any,
    using reply: @Sendable (LSPResult<Expected>) -> Void
  ) {
    guard let response = response as? Expected else {
      reply(.failure(.internalError("the response has the wrong type")))
      return
    }
    reply(.success(response))
  }
}
