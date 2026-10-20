import BylawsCore
import BylawsInterpreter
import BylawsPaths
import Foundation

package struct LintRunResult {
  package let rules: RuleRunResult
  package let changedPaths: [String]
  package let patch: String?
  package let inputPaths: Set<String>
}

package enum LintRunner {
  package enum CorrectionMode: Sendable {
    case none, preview, apply
  }

  package static func run(
    _ configuration: RuleRunConfiguration,
    testPackagePath: String? = nil,
    testFilters: [String] = [],
    skipTests: Bool = false,
    corrections: CorrectionMode = .none,
    reportOutputPath: String? = nil
  ) async throws -> LintRunResult {
    guard !SwiftTestingRuleSession.isCollecting else {
      throw CaptureError(
        "a test cannot start another lint run. Run Bylaws from the parent process"
      )
    }
    if let reportOutputPath { try ReportOutput.validate(reportOutputPath) }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "bylaws-lint-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: directory) }
    let initial = try await collect(
      configuration, testPackagePath: testPackagePath, testFilters: testFilters,
      skipTests: skipTests,
      captureSources: corrections != .none,
      directory: directory.appendingPathComponent("initial", isDirectory: true)
    )
    if let reportOutputPath {
      try ReportOutput.validate(
        reportOutputPath,
        inputPaths: initial.inputPaths
      )
    }
    guard corrections != .none, initial.result.outcome != .invalidRules,
          initial.result.outcome != .notConfigured
    else { return LintRunResult(
      rules: initial.result,
      changedPaths: [],
      patch: nil, inputPaths: initial.inputPaths
    ) }
    try await SourceCapture.validate(initial.captures)
    let plan = CorrectionPlan.prepare(
      reports: initial.result.reports,
      rootPath: configuration.root.string,
      reportPaths: configuration.reportPaths,
      protectedPaths: initial.protectedPaths
    )
    if corrections == .preview || plan.changes.isEmpty {
      return LintRunResult(
        rules: adding(plan.diagnostics, to: initial.result),
        changedPaths: [], patch: corrections == .preview ? plan.patch : nil,
        inputPaths: initial.inputPaths
      )
    }
    let changedPaths = try await plan.apply(captures: initial.captures)
    await RuleRunner.discardCaches(under: configuration.root.string)
    let verification: Collection
    do {
      verification = try await collect(
        configuration, testPackagePath: testPackagePath,
        testFilters: testFilters,
        skipTests: skipTests,
        captureSources: true,
        directory: directory.appendingPathComponent(
          "verification",
          isDirectory: true
        ),
        previousTestReports: initial.testReports
      )
      switch verification.result.outcome {
      case .invalidRules, .notConfigured:
        let diagnostics = verification.result.diagnostics.map(\.message)
        throw CaptureError(diagnostics.isEmpty
          ? "cannot load the rules during verification. Restore the rule definitions and run the command again"
          : diagnostics.joined(separator: "\n"))
      case .passed, .violations:
        break
      }
      try await SourceCapture.validate(verification.captures)
    } catch {
      throw VerificationError(
        changedPaths: changedPaths, reason: String(describing: error)
      )
    }
    return LintRunResult(
      rules: adding(plan.diagnostics, to: verification.result),
      changedPaths: changedPaths,
      patch: nil, inputPaths: initial.inputPaths.union(verification.inputPaths)
    )
  }

  struct Collection {
    let result: RuleRunResult
    let captures: [SourceCapture.Record]
    let protectedPaths: Set<String>
    let testReports: [SwiftTestingRuleReport]

    var inputPaths: Set<String> {
      protectedPaths.union(captures.flatMap(\.inputs).map(\.path))
    }
  }

  package struct VerificationError: Error, CustomStringConvertible {
    package let changedPaths: [String]
    package let reason: String

    package var description: String {
      "The correction changed these files:\n"
        + changedPaths.map { "  \($0)" }.joined(separator: "\n")
        + "\nCannot verify the corrected source: \(reason)"
        + "\nReview the changed files and run the command again."
    }
  }

  private static func adding(
    _ diagnostics: [Diagnostic], to result: RuleRunResult
  ) -> RuleRunResult {
    RuleRunResult(
      rootPath: result.rootPath,
      reports: result.reports,
      diagnostics: result.diagnostics + diagnostics,
      pathsThatDidNotParse: result.pathsThatDidNotParse,
      baselineEntries: result.baselineEntries,
      outcome: diagnostics.isEmpty ? result.outcome : .invalidRules
    )
  }
}
