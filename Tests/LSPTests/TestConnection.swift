import LanguageServerProtocol

#if canImport(os)
  import os
#else
  import Synchronization
#endif

final class TestConnection: Connection {
  #if canImport(os)
    private let notifications = OSAllocatedUnfairLock(
      initialState: [PublishDiagnosticsNotification]()
    )
  #else
    private let notifications = Mutex<[PublishDiagnosticsNotification]>([])
  #endif

  var publishedDiagnostics: [PublishDiagnosticsNotification] {
    notifications.withLock { $0 }
  }

  func send(_ notification: some NotificationType) {
    guard let notification = notification as? PublishDiagnosticsNotification
    else { return }
    notifications.withLock {
      $0.append(notification)
    }
  }

  func nextRequestID() -> RequestID {
    .number(0)
  }

  func send<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) {}
}
