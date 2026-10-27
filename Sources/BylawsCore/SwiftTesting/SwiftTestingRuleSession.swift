import BylawsSemantics
package import Foundation

package struct SwiftTestingRuleSession: Codable, Sendable, Equatable {
  package static let environmentKey = "BYLAWS_SWIFT_TESTING_RULE_SESSION"
  package static let protocolVersion = 5

  package let version: Int
  package let id: String
  package let directory: String
  package let rootPath: String
  package let isCorrection: Bool
  package let sourceOnly: Bool

  @TaskLocal package static var testingSession: SwiftTestingRuleSession?

  package init(
    id: String, directory: String, rootPath: String,
    isCorrection: Bool = false, sourceOnly: Bool = false
  ) {
    version = Self.protocolVersion
    self.id = id
    self.directory = directory
    self.rootPath = rootPath
    self.isCorrection = isCorrection
    self.sourceOnly = sourceOnly
  }

  package static var isCollecting: Bool {
    testingSession != nil
      || ProcessInfo.processInfo.environment[environmentKey] != nil
  }

  package static func active() throws -> SwiftTestingRuleSession? {
    if let testingSession { return testingSession }
    return try environmentSession.get()
  }

  package func write(_ report: SwiftTestingRuleReport) throws {
    try report.validate(in: self)
    let file = URL(fileURLWithPath: directory)
      .appendingPathComponent("report-\(UUID().uuidString).json")
    do {
      let encoder = JSONEncoder()
      encoder.userInfo[SwiftTestingSnapshotStore.codingKey] =
        SwiftTestingSnapshotStore(directory: file.deletingLastPathComponent())
      try encoder.encode(report).write(to: file, options: .atomic)
    } catch {
      throw SwiftTestingRuleSessionError
        .cannotWriteReport(error.reportableDescription)
    }
  }

  package static func reportDecoder(in directory: URL) throws -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.userInfo[SwiftTestingSnapshotStore.codingKey] =
      try SwiftTestingSnapshotStore.reading(in: directory)
    return decoder
  }

  package static func readReport(at file: URL) throws
    -> SwiftTestingRuleReport
  {
    try reportDecoder(in: file.deletingLastPathComponent()).decode(
      SwiftTestingRuleReport.self, from: Data(contentsOf: file)
    )
  }

  package static func readRequest(at file: URL) throws
    -> SwiftTestingRuleSession
  {
    let session: SwiftTestingRuleSession
    do {
      session = try JSONDecoder().decode(
        SwiftTestingRuleSession.self,
        from: Data(contentsOf: file)
      )
    } catch {
      throw SwiftTestingRuleSessionError
        .cannotReadRequest(error.reportableDescription)
    }
    guard session.version == protocolVersion else {
      throw SwiftTestingRuleSessionError.unsupportedVersion(session.version)
    }
    guard !session.id.isEmpty,
          session.directory.hasPrefix("/"),
          session.rootPath.hasPrefix("/")
    else { throw SwiftTestingRuleSessionError.malformedRequest }
    return session
  }

  private static let environmentSession: Result<
    SwiftTestingRuleSession?,
    any Error
  > =
    Result {
      guard let path = ProcessInfo.processInfo.environment[environmentKey]
      else { return nil }
      return try readRequest(at: URL(fileURLWithPath: path))
    }
}

package enum SwiftTestingRuleSessionError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  case cannotReadRequest(String)
  case unsupportedVersion(Int)
  case malformedRequest
  case mismatchedReport
  case malformedReport(String)
  case cannotWriteReport(String)
  case baselineRecording

  package var description: String {
    switch self {
    case let .cannotReadRequest(reason):
      "Cannot read the Swift Testing rule request: \(reason). Run the command again."
    case let .unsupportedVersion(version):
      "Swift Testing rule protocol version \(version) is unsupported. Use the same Bylaws version in the CLI and test package."
    case .malformedRequest:
      "Cannot read the Swift Testing rule request. Run the command again."
    case .mismatchedReport:
      "The Swift Testing rule report must belong to the current run. Run the command again."
    case let .malformedReport(reason):
      "Cannot use the Swift Testing rule report: \(reason). Check the test's reporting code and run again."
    case let .cannotWriteReport(reason):
      "Cannot write the Swift Testing rule report: \(reason). Check the output directory."
    case .baselineRecording:
      "Baseline recording cannot run during Swift Testing rule collection. Remove .record and run again."
    }
  }
}
