package import BylawsCore
import BylawsIndex
package import BylawsInterpreter
package import BylawsPaths
import BylawsSemantics
import Foundation

package struct RuleRunConfiguration {
  package var root: LexicalFilePath
  package var ruleFilePaths: [LexicalFilePath]
  package var only: [String]
  package var skip: [String]
  package var strict: Bool
  package var sourceOnly: Bool
  package var baseline: String?
  package var reportPaths: [String]
  package var parseCachePolicy: ParseCachePolicy
  package var overlay: SourceOverlay
  package var swiftPackageModules: String?

  package init(
    root: LexicalFilePath,
    ruleFilePaths: [LexicalFilePath] = [],
    only: [String] = [],
    skip: [String] = [],
    strict: Bool = false,
    sourceOnly: Bool = false,
    baseline: String? = nil,
    reportPaths: [String] = [],
    parseCachePolicy: ParseCachePolicy = .disabled,
    overlay: SourceOverlay = .empty,
    swiftPackageModules: String? = nil
  ) {
    self.root = root
    self.ruleFilePaths = ruleFilePaths
    self.only = only
    self.skip = skip
    self.strict = strict
    self.sourceOnly = sourceOnly
    self.baseline = baseline
    self.reportPaths = reportPaths
    self.parseCachePolicy = parseCachePolicy
    self.overlay = overlay
    self.swiftPackageModules = swiftPackageModules
  }
}

package struct RuleRunResult {
  package enum Outcome {
    case notConfigured
    case passed
    case violations
    case invalidRules
  }

  package let rootPath: String
  package let reports: [RuleReport]
  package let diagnostics: [Diagnostic]
  package let pathsThatDidNotParse: [String]
  package let baselineEntries: Set<Baseline.Entry>
  package let outcome: Outcome

  package var document: ReportDocument {
    ReportDocument(reports: reports, diagnostics: diagnostics)
  }
}

package struct LoadedRuleProgram {
  package let rootPath: String
  package let program: RuleProgram
}

package enum RuleRunner {
  package static func discardCaches(under rootPath: String) async {
    await CodebaseCache.shared.removeEntries(under: rootPath)
    await ProjectIndexCache.shared.removeEntries(under: rootPath)
  }

  package static func load(
    _ configuration: RuleRunConfiguration
  ) async -> LoadedRuleProgram {
    let rootPath = configuration.root.string
    var packageModuleIndex: PackageModuleIndex?
    if let path = configuration.swiftPackageModules {
      do {
        packageModuleIndex = try PackageModuleIndex(contentsOf: path)
      } catch {
        return failedLoad(
          rootPath: rootPath,
          message: "cannot read the SwiftPM module index at '\(path)': "
            + error.description
        )
      }
    }

    let program =
      if configuration.ruleFilePaths.isEmpty {
        await RuleProgram.discovered(
          atRoot: configuration.root,
          parseCachePolicy: configuration.parseCachePolicy,
          overlay: configuration.overlay,
          indexProvider: configuration.sourceOnly ? nil : BylawsIndexProvider(),
          packageModuleIndex: packageModuleIndex
        )
      } else {
        await RuleProgram.loaded(
          fromFiles: configuration.ruleFilePaths,
          parseCachePolicy: configuration.parseCachePolicy,
          overlay: configuration.overlay,
          indexProvider: configuration.sourceOnly ? nil : BylawsIndexProvider(),
          packageModuleIndex: packageModuleIndex
        )
      }
    return LoadedRuleProgram(rootPath: rootPath, program: program)
  }

  package static func run(
    _ configuration: RuleRunConfiguration
  ) async throws(CancellationError) -> RuleRunResult {
    if Task.isCancelled { throw CancellationError() }

    let loaded = await load(configuration)
    let rootPath = loaded.rootPath
    let program = loaded.program

    if Task.isCancelled { throw CancellationError() }

    if program.ruleFileStatus == .missing {
      return resultWithoutReports(
        rootPath: rootPath,
        diagnostics: program.diagnostics,
        outcome: .notConfigured
      )
    }

    guard program.errors.isEmpty else {
      return resultWithoutReports(
        rootPath: rootPath,
        diagnostics: program.diagnostics,
        outcome: .invalidRules,
        pathsThatDidNotParse: program.pathsThatDidNotParse
      )
    }

    let selection = RuleSelector.select(
      from: program.rules,
      only: configuration.only,
      skip: configuration.skip,
      defaultLocation: defaultLocation(
        rootPath: rootPath,
        rules: program.rules
      )
    )
    guard selection.diagnostics.isEmpty else {
      return resultWithoutReports(
        rootPath: rootPath,
        diagnostics: selection.diagnostics,
        outcome: .invalidRules
      )
    }

    let discovered = await DiscoveredBaselines.accepted(
      from: configuration.baseline,
      atRoot: rootPath
    )
    guard discovered.diagnostics.isEmpty else {
      return resultWithoutReports(
        rootPath: rootPath,
        diagnostics: discovered.diagnostics,
        outcome: .invalidRules
      )
    }
    let baselines = discovered.baselines

    let selected = selection.rules
    let allFindings: [Rule.Findings]
    do {
      allFindings = try await findingsOfEachRule(in: selected)
    } catch {
      switch error.cause {
      case .cancelled:
        throw CancellationError()
      case .codebase, .layering, .other:
        guard !Task.isCancelled else { throw CancellationError() }
        return invalidResult(
          rootPath: rootPath,
          location: selected.first { $0.id == error.rule }?.location
            ?? defaultLocation(rootPath: rootPath, rules: selected),
          message: error.description,
          pathsThatDidNotParse: error.pathsThatDidNotParse
        )
      }
    }

    var reports: [RuleReport] = []
    var baselineCheck = BaselineCheck(
      baselines: baselines,
      rootPath: rootPath
    )
    var recordedEntries: Set<Baseline.Entry> = []
    for (rule, findings) in zip(selected, allFindings) {
      let violations = findings.violations
      baselineCheck.observe(violations, from: rule.id)
      recordedEntries.formUnion(entries(
        from: violations,
        ruleID: rule.id,
        rootPath: rootPath
      ))
      reports.append(
        RuleReport(
          id: rule.id,
          name: rule.name,
          enforcement: rule.enforcement,
          hint: rule.hint,
          location: rule.location,
          violations: violations.removingOffenders(
            acceptedBy: baselines,
            for: rule.id,
            under: rootPath
          ),
          warnings: findings.warnings
        )
      )
    }

    let selectedRuleIDs: Set<Rule.ID>? =
      configuration.only.isEmpty && configuration.skip.isEmpty
        ? nil
        : Set(selected.map(\.id))
    let staleBaselineDiagnostics = baselineCheck.staleDiagnostics(
      checking: selectedRuleIDs
    )
    if !configuration.reportPaths.isEmpty {
      let scope = ReportPathScope(
        paths: configuration.reportPaths,
        rootPath: rootPath
      )
      reports = reports.map { $0.scoped(to: scope) }
    }

    let failing = reports.contains { report in
      !report.violations.isEmpty
        && (report.enforcement == .enforced || configuration.strict)
    }
    let diagnostics = program.diagnostics + staleBaselineDiagnostics
    return RuleRunResult(
      rootPath: rootPath,
      reports: reports,
      diagnostics: diagnostics,
      pathsThatDidNotParse: [],
      baselineEntries: recordedEntries,
      outcome: failing || !staleBaselineDiagnostics.isEmpty
        ? .violations
        : .passed
    )
  }

  private static func findingsOfEachRule(
    in rules: [Rule]
  ) async throws(RuleError) -> [Rule.Findings] {
    try await boundedConcurrentMap(
      rules,
      maximumConcurrentTasks: ProcessInfo.processInfo.activeProcessorCount
    ) { rule throws(RuleError) in
      try await rule.findings()
    }
  }

  private static func entries(
    from violations: Violations<Offender>,
    ruleID: Rule.ID,
    rootPath: String
  ) -> Set<Baseline.Entry> {
    Set(violations.offenders.map { offender in
      Baseline.Entry(offender: offender, for: ruleID, relativeTo: rootPath)
    })
  }

  private static func defaultLocation(
    rootPath: String,
    rules: [Rule]
  ) -> DeclarationLocation {
    rules.first?.location
      ?? DeclarationLocation.rulesFile(atRoot: rootPath)
  }

  private static func invalidResult(
    rootPath: String,
    location: DeclarationLocation? = nil,
    message: String,
    pathsThatDidNotParse: [String] = []
  ) -> RuleRunResult {
    resultWithoutReports(
      rootPath: rootPath,
      diagnostics: [
        Diagnostic(
          severity: .error,
          location: location ?? defaultLocation(rootPath: rootPath, rules: []),
          message: message
        ),
      ],
      outcome: .invalidRules,
      pathsThatDidNotParse: pathsThatDidNotParse
    )
  }

  private static func resultWithoutReports(
    rootPath: String,
    diagnostics: [Diagnostic],
    outcome: RuleRunResult.Outcome,
    pathsThatDidNotParse: [String] = []
  ) -> RuleRunResult {
    RuleRunResult(
      rootPath: rootPath,
      reports: [],
      diagnostics: diagnostics,
      pathsThatDidNotParse: pathsThatDidNotParse,
      baselineEntries: [],
      outcome: outcome
    )
  }

  private static func failedLoad(
    rootPath: String,
    message: String
  ) -> LoadedRuleProgram {
    LoadedRuleProgram(
      rootPath: rootPath,
      program: RuleProgram(
        loadedRules: [],
        diagnostics: [
          Diagnostic(
            severity: .error,
            location: defaultLocation(rootPath: rootPath, rules: []),
            message: message
          ),
        ]
      )
    )
  }
}
