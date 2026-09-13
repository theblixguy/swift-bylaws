import BylawsCore
import BylawsInterpreter
import BylawsSemantics

struct BaselineCheck {
  private let baselines: [DiscoveredBaseline]
  private let rootPath: String
  private var matchesByPath: [String: Set<Baseline.Entry>] = [:]

  init(baselines: [DiscoveredBaseline], rootPath: String) {
    self.baselines = baselines
    self.rootPath = rootPath
  }

  mutating func observe(
    _ violations: Violations<Offender>,
    from rule: Rule.ID
  ) {
    for offender in violations.offenders {
      let entry = Baseline.Entry(
        offender: offender,
        for: rule,
        relativeTo: rootPath
      )
      for baseline in baselines where baseline.entries.contains(entry) {
        guard baseline.applies(
          to: offender.affectedPath ?? offender.location.filePath,
          underRoot: rootPath
        ) else { continue }
        matchesByPath[baseline.path, default: []].insert(entry)
      }
    }
  }

  func staleDiagnostics(
    checking ruleIDs: Set<Rule.ID>?
  ) -> [Diagnostic] {
    baselines.flatMap { baseline in
      let matches = matchesByPath[baseline.path, default: []]
      return baseline.entries.sorted().compactMap { entry -> Diagnostic? in
        guard ruleIDs?.contains(entry.rule) ?? true,
              !matches.contains(entry)
        else { return nil }
        return Diagnostic(
          severity: .error,
          location: DeclarationLocation.start(of: baseline.path),
          message: "baseline entry no longer matches a violation: "
            + "\(entry.rule): \(entry.acceptedDescription)",
          hint: "record the baseline again to remove stale entries"
        )
      }
    }
  }
}
