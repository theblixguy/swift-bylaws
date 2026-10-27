package import BylawsCore
import BylawsSemantics
import Foundation
import Subprocess

package struct SwiftPMTestRun: Sendable {
  package let reports: [SwiftTestingRuleReport]
  package let captures: [SourceCapture.Record]
  package let protectedSourcePaths: [String]
  package let packageRootPath: String
  package let indexStorePath: String?
}

package enum SwiftPMTestRunner {
  @concurrent
  package static func collect(
    atRoot rootPath: String,
    filters: [String] = [],
    freshIndex: Bool = false,
    swiftPMArguments: [String] = [],
    session: SwiftTestingRuleSession
  ) async throws -> SwiftPMTestRun {
    guard rootPath.hasPrefix("/"), session.rootPath.hasPrefix("/"),
          session.directory.hasPrefix("/")
    else { throw SwiftTestingRuleSessionError.malformedRequest }
    let directory = URL(fileURLWithPath: session.directory)
    let captureDirectory = directory.appendingPathComponent(
      "captures",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: captureDirectory, withIntermediateDirectories: true
    )
    let filter = try combinedFilter(filters)
    let scratch = directory.appendingPathComponent("build", isDirectory: true)
    var environment = subprocessEnvironment()
    let index = try await prepareIndexBuild(
      freshIndex: freshIndex, scratch: scratch, rootPath: rootPath,
      directory: directory, swiftPMArguments: swiftPMArguments,
      environment: environment
    )
    try await resolvePackage(
      atRoot: rootPath, directory: directory,
      swiftPMArguments: swiftPMArguments + index.arguments,
      environment: environment
    )
    let packageCaptures = try await captureInputs(
      atRoot: rootPath, directory: directory,
      scratch: freshIndex ? scratch : nil,
      swiftPMArguments: swiftPMArguments + index.arguments,
      environment: environment,
      sessionID: session.id
    )
    let metadata = try await SwiftPMCommand.run(
      arguments: ["package"] + swiftPMArguments + index.arguments
        + ["--package-path", rootPath, "describe", "--type", "json"],
      rootPath: rootPath, directory: directory, environment: environment
    )
    let package = try decodeOutput(
      PackageDescription.self, from: metadata, atRoot: rootPath
    )
    let hasTests = package.targets.contains(where: { $0.type == "test" })
    guard hasTests else {
      throw SwiftPMTestRunnerError.noTestTargets
    }

    let request = directory.appendingPathComponent("request.json")
    try JSONEncoder().encode(session).write(to: request, options: .atomic)
    environment[SwiftTestingRuleSession.environmentKey] = request.path
    let purpose: RuleRunPurpose = if session.isCorrection {
      .proposeCorrections
    } else {
      .checkOnly
    }
    environment[RuleRunPurpose.environmentKey] = purpose.rawValue
    environment["BYLAWS_SOURCE_CAPTURE_DIRECTORY"] = captureDirectory.path
    environment["BYLAWS_SOURCE_CAPTURE_ID"] = session.id
    if session.isCorrection { environment["BYLAWS_CORRECTION_ACTIVE"] = "1" }
    if session.sourceOnly { environment["BYLAWS_SOURCE_ONLY"] = "1" }
    if let storePath = index.storePath {
      environment["BYLAWS_INDEX_STORE"] = storePath
      environment["BYLAWS_FRESH_INDEX_STORE"] = storePath
      environment["BYLAWS_FRESH_INDEX_ROOT"] = rootPath
    }
    let events = directory.appendingPathComponent("events.jsonl")
    var arguments = ["test"] + swiftPMArguments + index.arguments + [
      "--package-path", rootPath,
      "--event-stream-version", "0", "--event-stream-output-path", events.path,
    ]
    if let filter { arguments += ["--filter", filter] }
    let result = try await SwiftPMCommand.run(
      arguments: arguments,
      rootPath: rootPath, directory: directory, environment: environment
    )
    try checkStatus(result)
    let summary = try readOutput(at: events) { data in
      try SwiftTestingRunSummary(
        data: data, requiresMatchingTests: filter != nil
      )
    }
    let reports = try readReports(
      in: directory,
      session: session,
      summary: summary
    )
    let captures = packageCaptures + (try readCaptures(
      in: captureDirectory,
      session: session
    ))
    return SwiftPMTestRun(
      reports: reports,
      captures: captures,
      protectedSourcePaths: package.targets.filter { $0.type == "test" }
        .flatMap { target in
          let packageRoot = URL(fileURLWithPath: rootPath)
          let targetRoot = if let path = target.path {
            if path.hasPrefix("/") {
              URL(fileURLWithPath: path)
            } else {
              packageRoot.appendingPathComponent(path)
            }
          } else {
            packageRoot
          }
          return (target.sources ?? []).map {
            targetRoot.appendingPathComponent($0).standardizedFileURL.path
          }
        }.sorted(),
      packageRootPath: rootPath,
      indexStorePath: index.storePath
    )
  }

  package static func combinedFilter(_ filters: [String]) throws -> String? {
    guard !filters.isEmpty else { return nil }
    for filter in filters {
      do { _ = try NSRegularExpression(pattern: filter) }
      catch { throw SwiftPMTestRunnerError.malformedFilter(filter) }
    }
    return filters.map { "(?:\($0))" }.joined(separator: "|")
  }

  private static func readReports(
    in directory: URL,
    session: SwiftTestingRuleSession,
    summary: SwiftTestingRunSummary
  ) throws -> [SwiftTestingRuleReport] {
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    .filter {
      $0.lastPathComponent.hasPrefix("report-") && $0.pathExtension == "json"
    }
    let decoder = try SwiftTestingRuleSession.reportDecoder(in: directory)
    let reports = try files.map { file in
      let (report, canonical) = try readOutput(at: file) { data in
        let report = try decoder.decode(SwiftTestingRuleReport.self, from: data)
        let canonical = try JSONSerialization.data(
          withJSONObject: JSONSerialization.jsonObject(with: data),
          options: .sortedKeys
        )
        return (report, canonical)
      }
      try report.validate(in: session)
      guard summary.startedTestIDs.contains(report.testID) else {
        throw SwiftPMTestRunnerError.mismatchedReport
      }
      return (report: report, canonical: canonical)
    }
    return reports.sorted { lhs, rhs in
      let left = lhs.report
      let right = rhs.report
      if left.ruleID != right.ruleID {
        return left.ruleID.rawValue < right.ruleID.rawValue
      }
      if left.testID != right.testID { return left.testID < right.testID }
      if left.location.filePath != right.location.filePath {
        return left.location.filePath < right.location.filePath
      }
      if left.location.line != right.location.line {
        return left.location.line < right.location.line
      }
      if left.location.column != right.location.column {
        return left.location.column < right.location.column
      }
      return lhs.canonical.lexicographicallyPrecedes(rhs.canonical)
    }.map(\.report)
  }

  private static func readCaptures(
    in directory: URL,
    session: SwiftTestingRuleSession
  ) throws -> [SourceCapture.Record] {
    try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
      .map { file in
        let record = try readOutput(at: file) { data in
          try JSONDecoder().decode(SourceCapture.Record.self, from: data)
        }
        guard record.sessionID == session.id else {
          throw SwiftPMTestRunnerError.mismatchedCapture
        }
        return record
      }
  }

  private static func readOutput<Value>(
    at file: URL,
    decode: (Data) throws -> Value
  ) throws -> Value {
    do { return try decode(Data(contentsOf: file)) }
    catch let error as SwiftPMTestRunnerError { throw error }
    catch {
      throw SwiftPMTestRunnerError.cannotReadOutput(
        file.path,
        String(describing: error)
      )
    }
  }

  static func decodeOutput<Value: Decodable>(
    _ type: Value.Type,
    from result: SwiftPMCommand.Result,
    atRoot rootPath: String
  ) throws -> Value {
    try checkStatus(result)
    do { return try JSONDecoder().decode(type, from: result.standardOutput) }
    catch {
      throw SwiftPMTestRunnerError.cannotReadCommandOutput(
        command: "swift " + result.arguments.joined(separator: " "),
        root: rootPath, reason: String(describing: error)
      )
    }
  }

  static func subprocessEnvironment(
    _ inherited: [String: String] = ProcessInfo.processInfo.environment
  ) -> [String: String] {
    var environment = inherited
    for key in [
      SwiftTestingRuleSession.environmentKey, "BYLAWS_SOURCE_CAPTURE_DIRECTORY",
      "BYLAWS_SOURCE_CAPTURE_ID", "BYLAWS_FRESH_INDEX_STORE",
      "BYLAWS_FRESH_INDEX_ROOT", "BYLAWS_CORRECTION_ACTIVE",
      "BYLAWS_SOURCE_ONLY",
    ] {
      environment.removeValue(forKey: key)
    }
    return environment
  }

  @concurrent
  static func resolvePackage(
    atRoot rootPath: String, directory: URL,
    swiftPMArguments: [String], environment: [String: String]
  ) async throws {
    let result = try await SwiftPMCommand.run(
      arguments: ["package"] + swiftPMArguments
        + ["--package-path", rootPath, "resolve"],
      rootPath: rootPath, directory: directory, environment: environment
    )
    try checkStatus(result)
  }

  static func checkStatus(_ result: SwiftPMCommand.Result) throws {
    guard !result.terminationStatus.isSuccess else { return }
    let output =
      "swift \(result.arguments.joined(separator: " "))\n"
        + String(
          decoding: result.standardOutput + result.standardError,
          as: UTF8.self
        )
    switch result.terminationStatus {
    case let .exited(status):
      throw SwiftPMTestRunnerError.processFailed(
        status, output
      )
    case let .signaled(signal):
      throw SwiftPMTestRunnerError.processSignaled(signal, output)
    }
  }

  private struct PackageDescription: Decodable {
    let targets: [Target]
    struct Target: Decodable {
      let type: String
      let path: String?
      let sources: [String]?
    }
  }
}
