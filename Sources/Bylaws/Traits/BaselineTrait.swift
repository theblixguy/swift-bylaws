#if canImport(Testing)
  public import BylawsCore
  import BylawsSemantics
  import Foundation
  @_weakLinked public import Testing

  /// The check or recording mode selected by a `.baseline(_:mode:)` trait.
  public enum BaselineMode: Sendable {
    /// Keeps known violations visible without failing.
    ///
    /// New violations fail.
    case check

    /// Rewrites the baseline file and deliberately fails the run.
    case record
  }

  /// A trait that checks failures against a recorded baseline.
  ///
  /// Apply it to a suite. Check mode leaves recorded failures visible. New
  /// failures fail the test. Record mode rewrites the baseline file, then
  /// deliberately fails. Remove record mode before the CI run.
  ///
  /// An entry names the rule, declaration and project-relative file path it
  /// accepts. ``Bylaws/BylawsCore/Rule/report(enforcement:sourceLocation:)`` includes the
  /// declaration. For assertions on individual declarations, apply
  /// ``AnnotatesViolationsTrait``. Other failures share one entry for each
  /// rule and file.
  ///
  /// Record with a full test run. A check run fails when a completed rule no
  /// longer produces one of its recorded entries. Skipped rules and
  /// individually run cases of a parameterised native rule keep their entries
  /// unchecked.
  public struct BaselineTrait: TestTrait, SuiteTrait, TestScoping, Sendable {
    /// Baselines include every test and nested suite.
    public var isRecursive: Bool { true }

    let baseline: Baseline
    let mode: BaselineMode
    private let recorder = BaselineRecorder()

    public func provideScope(
      for test: Test,
      testCase: Test.Case?,
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      if let completedRuleObserver = TraitScope.completedRuleObserver {
        try await function()
        if let ruleID = Self.completedNativeRule(for: test) {
          completedRuleObserver(ruleID)
        }
        return
      }

      // Testing calls issue handlers synchronously.
      let (stream, continuation) = AsyncStream<BaselineObservation>.makeStream()
      let (ruleStream, ruleContinuation) = AsyncStream<Rule.ID>.makeStream()
      let known = Set(baseline.entries)
      let mode = mode
      let projectRoot = projectRoot(for: baseline)
      let observation: @Sendable (Issue) -> BaselineObservation? = { issue in
        Self.observation(of: issue, known: known, projectRoot: projectRoot)
      }
      let suppresses: @Sendable (BaselineObservation) -> Bool = { observation in
        observation.known || mode == .record
      }
      let handling = IssueHandlingTrait.compactMapIssues { issue in
        guard let observation = observation(issue) else { return issue }
        continuation.yield(observation)
        #if compiler(>=6.3)
          guard suppresses(observation) else { return issue }
          var issue = issue
          issue.severity = .warning
          return issue
        #else
          return issue
        #endif
      }

      var deferredTestError: (any Error)?
      do {
        try await TraitScope.$completedRuleObserver.withValue({ ruleID in
          ruleContinuation.yield(ruleID)
        }) {
          #if compiler(>=6.3)
            try await handling.provideScope(for: test, testCase: testCase) {
              try await function()
            }
          #else
            try await withKnownIssue(isIntermittent: true) {
              try await handling.provideScope(for: test, testCase: testCase) {
                try await function()
              }
            } matching: { issue in
              observation(issue).map(suppresses) ?? false
            }
          #endif
        }
      } catch {
        deferredTestError = error
      }
      continuation.finish()
      ruleContinuation.finish()

      var observations: [BaselineObservation] = []
      for await observation in stream {
        observations.append(observation)
      }
      var completedRules = Set<Rule.ID>()
      for await ruleID in ruleStream {
        completedRules.insert(ruleID)
      }
      if deferredTestError == nil,
         let ruleID = Self.completedNativeRule(for: test)
      {
        completedRules.insert(ruleID)
      }

      switch mode {
      case .check:
        reportUnmatchedEntries(
          given: observations,
          completedRules: completedRules
        )
      case .record:
        await recordAndFail(
          with: observations,
          completedRules: completedRules
        )
      }
      if let deferredTestError {
        throw deferredTestError
      }
    }

    private static func observation(
      of issue: Issue,
      known: Set<Baseline.Entry>,
      projectRoot: String?
    ) -> BaselineObservation? {
      if let violation = TraitScope.reportedViolation {
        let reported = baselineLocation(
          of: violation.offender.affectedPath ?? violation.offender.location
            .filePath,
          under: projectRoot
        )
        let entry = Baseline.Entry(
          offender: violation.offender,
          for: violation.rule,
          at: reported.filePath,
          relativeTo: reported.root
        )
        return BaselineObservation(entry: entry, known: known.contains(entry))
      }
      #if compiler(>=6.3)
        guard issue.severity == .error else { return nil }
      #endif
      let declaration = TraitScope.declaration
      let currentRule = Test.current.map {
        Rule.ID($0.displayName ?? $0.name)
      }
      guard let rule = (declaration as? Rule)?.id ?? currentRule
      else { return nil }
      let reported = baselineLocation(
        of: declaration?.location.filePath
          ?? issue.sourceLocation?.bylawsFilePath ?? "",
        under: projectRoot
      )
      let entry = Baseline.Entry(
        rule: rule,
        declaration: (declaration as? any Named)?.name ?? "",
        file: Baseline.Entry.fileIdentity(
          for: reported.filePath,
          relativeTo: reported.root
        )
      )
      return BaselineObservation(entry: entry, known: known.contains(entry))
    }

    private static func baselineLocation(
      of reportedFilePath: String,
      under projectRoot: String?
    ) -> (filePath: String, root: String?) {
      let filePath = baselinePath(reportedFilePath)
      return (
        filePath,
        filePath.hasPrefix("/virtual/") ? "/virtual" : projectRoot
      )
    }

    private func projectRoot(for baseline: Baseline) -> String? {
      if let codebase = Codebase.current,
         let root = try? codebase.resolvedRootPath()
      {
        return Self.canonicalPath(root)
      }
      return try? Self.canonicalPath(
        Codebase.automaticRoot(above: baseline.file)
      )
    }

    private func reportUnmatchedEntries(
      given observations: [BaselineObservation],
      completedRules: Set<Rule.ID>
    ) {
      let matched = Set(observations.filter(\.known).map(\.entry))
      let unmatchedEntries = Self.unmatchedEntries(
        in: baseline,
        matched: matched,
        completedRules: completedRules
      )
      guard !unmatchedEntries.isEmpty else { return }
      let listing = unmatchedEntries
        .map { "  - \($0.rule): \($0.acceptedDescription)" }
        .joined(separator: "\n")
      let staleCount = unmatchedEntries.count
      let entry = staleCount == 1 ? "entry" : "entries"
      Issue.record(
        """
        The baseline '\(baseline.name)' has \(staleCount) stale \(entry). \
        Run once with .record to remove them:
        \(listing)
        """
      )
    }

    package static func unmatchedEntries(
      in baseline: Baseline,
      matched: Set<Baseline.Entry>,
      completedRules: Set<Rule.ID>
    ) -> [Baseline.Entry] {
      baseline.entries.filter {
        completedRules.contains($0.rule) && !matched.contains($0)
      }
    }

    private static func completedNativeRule(for test: Test) -> Rule.ID? {
      guard !test.isSuite, !test.isParameterized else { return nil }
      return Rule.ID(test.displayName ?? test.name)
    }

    private func recordAndFail(
      with observations: [BaselineObservation],
      completedRules: Set<Rule.ID>
    ) async {
      do {
        let total = try await recorder.record(
          Set(observations.map(\.entry)),
          completedRules: completedRules,
          in: baseline
        )
        Issue.record(
          """
          Recorded \(total) violation\(total == 1 ? "" : "s") to \
          \(baseline.file). Remove .record and run again.
          """
        )
      } catch {
        Issue.record(
          "Could not write the baseline file '\(baseline.file)': \(error)"
        )
      }
    }

    private static func canonicalPath(_ path: String) -> String {
      URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func baselinePath(_ path: String) -> String {
      path.hasPrefix("/virtual/") ? path : canonicalPath(path)
    }

    private struct BaselineObservation: Sendable {
      let entry: Baseline.Entry
      let known: Bool
    }
  }

  extension Trait where Self == BaselineTrait {
    /// Checks failures against `baseline`, or rewrites it in `.record` mode.
    public static func baseline(
      _ baseline: Baseline,
      mode: BaselineMode = .check
    ) -> Self {
      Self(baseline: baseline, mode: mode)
    }
  }

  extension SourceLocation {
    fileprivate var bylawsFilePath: String {
      #if compiler(>=6.3)
        filePath
      #else
        _filePath
      #endif
    }
  }
#endif
