import BylawsRunner
import Foundation
import Testing

@Suite("Swift Testing run summary")
struct SwiftTestingRunSummaryTests {
  @Test("Matched parameterised test with zero cases completes")
  func emptyCases() throws {
    let summary = try SwiftTestingRunSummary(
      data: data([
        test(), event("runStarted"), event("testStarted", testID: "rule"),
        event("testEnded", testID: "rule"), event("runEnded"),
      ]), requiresMatchingTests: true
    )

    #expect(summary.tests.count == 1)
    #expect(summary.caseCount == 0)
    #expect(summary.caseCounts == ["rule": 0])
    #expect(summary.startedTestIDs == ["rule"])
  }

  @Test("Skipped and unstarted functions cannot prove empty outcomes")
  func skippedCases() throws {
    let summary = try SwiftTestingRunSummary(
      data: data([
        test(), event("runStarted"), event("testSkipped", testID: "rule"),
        event("runEnded"),
      ]), requiresMatchingTests: true
    )

    #expect(summary.skippedTestIDs == ["rule"])
    #expect(summary.caseCounts.isEmpty)
  }

  @Test("Case completion must match the same function")
  func mismatchedCases() {
    #expect(throws: SwiftPMTestRunnerError.incompleteRun) {
      try SwiftTestingRunSummary(
        data: data([
          event("runStarted"), event("testStarted", testID: "rule"),
          event("testCaseStarted", testID: "rule"),
          event("testCaseEnded", testID: "other"),
          event("testEnded", testID: "rule"), event("runEnded"),
        ]), requiresMatchingTests: false
      )
    }
  }

  @Test("Filter with no matching functions fails")
  func unmatchedFilter() {
    #expect(throws: SwiftPMTestRunnerError.noMatchingTests) {
      try SwiftTestingRunSummary(
        data: data([event("runStarted"), event("runEnded")]),
        requiresMatchingTests: true
      )
    }
  }

  @Test("Incomplete run fails", arguments: IncompleteRunCase.allCases)
  func incompleteRun(_ mode: IncompleteRunCase) {
    var records = [event("runStarted")]
    switch mode {
    case .missingEnd: break
    case .openTest: records.append(event("testStarted", testID: "rule"))
    case .cancelled: records.append(event("testCancelled", testID: "rule"))
    case .duplicateStart: records.append(event("runStarted"))
    case .eventBeforeRun: records.insert(event("futureEvent"), at: 0)
    case .eventAfterRun:
      records += [event("runEnded"), event("testStarted", testID: "rule")]
    }
    if mode != .missingEnd { records.append(event("runEnded")) }

    #expect(throws: SwiftPMTestRunnerError.incompleteRun) {
      try SwiftTestingRunSummary(
        data: data(records),
        requiresMatchingTests: false
      )
    }
  }

  @Test("Unfinished case blocks completed function")
  func unfinishedCase() {
    #expect(throws: SwiftPMTestRunnerError.incompleteRun) {
      try SwiftTestingRunSummary(
        data: data([
          event("runStarted"), event("testStarted", testID: "rule"),
          event("testCaseStarted", testID: "rule"),
          event("testEnded", testID: "rule"), event("runEnded"),
        ]), requiresMatchingTests: false
      )
    }
  }

  @Test("Completed case permits completed function")
  func completedCase() throws {
    let summary = try SwiftTestingRunSummary(
      data: data([
        event("runStarted"), event("testStarted", testID: "rule"),
        event("testCaseStarted", testID: "rule"),
        event("testCaseEnded", testID: "rule"),
        event("testEnded", testID: "rule"), event("runEnded"),
      ]), requiresMatchingTests: false
    )

    #expect(summary.caseCount == 1)
  }

  @Test("Expected offender issue permits collection")
  func expectedIssue() throws {
    let summary = try SwiftTestingRunSummary(
      data: data([
        event("runStarted"),
        #"{"version":0,"kind":"event","payload":{"kind":"issueRecorded","issue":{"isKnown":true}}}"#,
        event("runEnded"),
      ]), requiresMatchingTests: false
    )

    #expect(summary.caseCount == 0)
  }

  @Test("Unrelated failure blocks collection")
  func unrelatedFailure() {
    #expect(throws: SwiftPMTestRunnerError.unexpectedIssue("rule")) {
      try SwiftTestingRunSummary(
        data: data([
          event("runStarted"),
          #"{"version":0,"kind":"event","payload":{"kind":"issueRecorded","testID":"rule","issue":{"isKnown":false}}}"#,
          event("runEnded"),
        ]), requiresMatchingTests: false
      )
    }
  }

  @Test("Malformed run output fails")
  func malformedOutput() {
    #expect(throws: DecodingError.self) {
      try SwiftTestingRunSummary(
        data: Data("{broken}".utf8), requiresMatchingTests: false
      )
    }
  }

  @Test("Unsupported version fails before payload decoding", arguments: [
    #"{"version":99,"kind":"test","payload":42}"#,
    #"{"version":99,"kind":"event","payload":42}"#,
    #"{"version":99,"kind":"futureRecord","payload":42}"#,
  ])
  func unsupportedVersion(_ record: String) {
    #expect(throws: SwiftPMTestRunnerError.unsupportedEventVersion) {
      try SwiftTestingRunSummary(
        data: data([record]), requiresMatchingTests: false
      )
    }
  }

  @Test("Unknown event kinds permit forward compatibility")
  func unknownEvent() throws {
    let summary = try SwiftTestingRunSummary(
      data: data([
        event("runStarted"),
        event("futureEvent"),
        event("runEnded"),
      ]),
      requiresMatchingTests: false
    )

    #expect(summary.tests.isEmpty)
  }

  @Test("Unknown record kinds leave payload unread")
  func unknownRecord() throws {
    let summary = try SwiftTestingRunSummary(
      data: data([
        #"{"version":0,"kind":"futureRecord","payload":42}"#,
        event("runStarted"), event("runEnded"),
      ]),
      requiresMatchingTests: false
    )

    #expect(summary.tests.isEmpty)
    #expect(summary.startedTestIDs.isEmpty)
    #expect(summary.caseCount == 0)
  }

  @Test("Test filters combine as alternatives")
  func combinedFilters() throws {
    #expect(try SwiftPMTestRunner
      .combinedFilter(["One", "Two"]) == "(?:One)|(?:Two)")
    #expect(try SwiftPMTestRunner.combinedFilter([]) == nil)
    #expect(throws: SwiftPMTestRunnerError.malformedFilter("[")) {
      try SwiftPMTestRunner.combinedFilter(["["])
    }
  }

  enum IncompleteRunCase: CaseIterable, Sendable {
    case missingEnd, openTest, cancelled, duplicateStart
    case eventBeforeRun, eventAfterRun
  }

  private func data(_ records: [String]) -> Data {
    Data((records.joined(separator: "\n") + "\n").utf8)
  }

  private func test() -> String {
    #"{"version":0,"kind":"test","payload":{"id":"rule","name":"holds()","kind":"function","isParameterized":true}}"#
  }

  private func event(_ kind: String, testID: String? = nil) -> String {
    let id = testID.map { ",\"testID\":\"\($0)\"" } ?? ""
    return "{\"version\":0,\"kind\":\"event\",\"payload\":{\"kind\":\"\(kind)\"\(id)}}"
  }
}
