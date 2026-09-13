import Synchronization
import Testing

@available(macOS 15, *)
final class IssueRecorder: Sendable {
  enum Message: Sendable {
    case equalTo(String)
    case containing(String)

    fileprivate func matches(_ message: String) -> Bool {
      switch self {
      case let .equalTo(expected):
        message == expected
      case let .containing(expected):
        message.contains(expected)
      }
    }
  }

  enum Severity: Equatable, Sendable {
    case any
    case error
    case warning
  }

  struct Record: Equatable, Sendable {
    let message: String
    let location: String?
  }

  private let expectedMessage: Message
  private let expectedSeverity: Severity
  private let records = Mutex<[Record]>([])

  init(_ expectedMessage: Message, severity: Severity = .any) {
    self.expectedMessage = expectedMessage
    expectedSeverity = severity
  }

  func record(_ issue: Issue) -> Issue? {
    let message = issue.comments.first?.rawValue ?? ""
    guard expectedMessage.matches(message) else { return issue }
    #if compiler(>=6.3)
      guard expectedSeverity != .warning || issue.severity == .warning else {
        return issue
      }
      guard expectedSeverity != .error || issue.severity == .error else {
        return issue
      }
    #endif
    let location = issue.sourceLocation.map {
      "\($0.fileID):\($0.line):\($0.column)"
    }
    records.withLock { $0.append(Record(message: message, location: location)) }
    return nil
  }

  func takeRecords() -> [Record] {
    records.withLock {
      let result = $0
      $0.removeAll()
      return result
    }
  }
}
