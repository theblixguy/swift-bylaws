package import Foundation

package struct SwiftTestingTestMetadata: Codable, Sendable, Equatable {
  package let id: String
  package let name: String
  package let displayName: String?
  package let kind: String
  package let isParameterized: Bool?
}

package struct SwiftTestingRunSummary: Sendable {
  package let tests: [SwiftTestingTestMetadata]
  package let startedTestIDs: Set<String>
  package let caseCount: Int
  package let caseCounts: [String: Int]
  package let skippedTestIDs: Set<String>

  package init(data: Data, requiresMatchingTests: Bool) throws {
    var tests: [SwiftTestingTestMetadata] = []
    var started: Set<String> = []
    var ended: Set<String> = []
    var startedCases: [String: Int] = [:]
    var endedCases: [String: Int] = [:]
    var skipped: Set<String> = []
    var phase = RunPhase.notStarted
    let decoder = JSONDecoder()
    for line in data.split(separator: 0x0A) {
      let record = try decoder.decode(Record.self, from: Data(line))
      switch record.payload {
      case let .test(test):
        tests.append(test)
      case let .event(event):
        guard phase != .finished,
              phase == .running || event.kind == .runStarted
        else {
          throw SwiftPMTestRunnerError.incompleteRun
        }
        switch event.kind {
        case .runStarted:
          guard phase == .notStarted else {
            throw SwiftPMTestRunnerError.incompleteRun
          }
          phase = .running
        case .runEnded:
          phase = .finished
        case .testStarted:
          guard let id = event.testID,
                started.insert(id).inserted
          else { throw SwiftPMTestRunnerError.incompleteRun }
        case .testEnded:
          guard let id = event.testID, started.contains(id),
                ended.insert(id).inserted
          else { throw SwiftPMTestRunnerError.incompleteRun }
        case .testCaseStarted:
          guard let id = event.testID, started.contains(id),
                !ended.contains(id)
          else { throw SwiftPMTestRunnerError.incompleteRun }
          startedCases[id, default: 0] += 1
        case .testCaseEnded:
          guard let id = event.testID,
                endedCases[id, default: 0] < startedCases[id, default: 0]
          else { throw SwiftPMTestRunnerError.incompleteRun }
          endedCases[id, default: 0] += 1
        case .testSkipped:
          guard let id = event.testID, !started.contains(id),
                skipped.insert(id).inserted
          else { throw SwiftPMTestRunnerError.incompleteRun }
        case .testCancelled, .testCaseCancelled:
          throw SwiftPMTestRunnerError.incompleteRun
        case .issueRecorded:
          guard let issue = event.issue else {
            throw SwiftPMTestRunnerError.incompleteRun
          }
          if issue.isFailure
            ?? (!issue.isKnown && issue.severity != "warning"
              && !event.messages.contains { $0.symbol == "warning" })
          {
            throw SwiftPMTestRunnerError.unexpectedIssue(event.testID)
          }
        case .valueAttached, nil: break
        }
      case .unknown: break
      }
    }
    guard phase == .finished, started == ended,
          startedCases == endedCases
    else { throw SwiftPMTestRunnerError.incompleteRun }
    if requiresMatchingTests,
       !tests.contains(where: { $0.kind == "function" })
    {
      throw SwiftPMTestRunnerError.noMatchingTests
    }
    self.tests = tests
    startedTestIDs = started
    caseCount = startedCases.values.reduce(0, +)
    caseCounts = tests.filter {
      $0.kind == "function" && started.contains($0.id)
    }.reduce(into: [:]) {
      $0[$1.id] = startedCases[$1.id, default: 0]
    }
    skippedTestIDs = skipped
  }

  private enum RunPhase {
    case notStarted, running, finished
  }

  private struct Record: Decodable {
    let payload: Payload

    enum Payload {
      case test(SwiftTestingTestMetadata)
      case event(Event)
      case unknown
    }

    enum Kind: String {
      case test, event
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      guard try container.decode(Int.self, forKey: .version) == 0 else {
        throw SwiftPMTestRunnerError.unsupportedEventVersion
      }
      switch Kind(rawValue: try container.decode(String.self, forKey: .kind)) {
      case .test:
        payload = .test(try container.decode(
          SwiftTestingTestMetadata.self, forKey: .payload
        ))
      case .event:
        payload = .event(try container.decode(Event.self, forKey: .payload))
      case nil:
        payload = .unknown
      }
    }

    private enum CodingKeys: CodingKey {
      case version, kind, payload
    }
  }

  private struct Event: Decodable {
    let kind: Kind?
    let testID: String?
    let issue: RecordedIssue?
    let messages: [Message]

    enum Kind: String {
      case runStarted, runEnded
      case testStarted, testEnded, testSkipped, testCancelled
      case testCaseStarted, testCaseEnded, testCaseCancelled
      case issueRecorded, valueAttached
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      kind = Kind(rawValue: try container.decode(String.self, forKey: .kind))
      testID = try container.decodeIfPresent(String.self, forKey: .testID)
      issue = try container.decodeIfPresent(RecordedIssue.self, forKey: .issue)
      messages = try container.decodeIfPresent(
        [Message].self,
        forKey: .messages
      ) ?? []
    }

    private enum CodingKeys: CodingKey {
      case kind, testID, issue, messages
    }
  }

  private struct RecordedIssue: Decodable {
    let isKnown: Bool
    let isFailure: Bool?
    let severity: String?
  }

  private struct Message: Decodable {
    let symbol: String
  }
}
