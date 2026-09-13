import BylawsCore
import BylawsPaths
import BylawsSemantics

struct ExcludedSubtrees {
  private let directories: [LexicalFilePath]

  init(subtrees: [String], under roots: [String]) {
    directories = roots.flatMap { root in
      subtrees.map { LexicalFilePath(root).appending($0) }
    }
  }

  var isEmpty: Bool { directories.isEmpty }

  func filteringOffenders(from findings: Rule.Findings) -> Rule.Findings {
    guard !isEmpty else { return findings }
    return Rule.Findings(
      checks: findings.checks.map { check in
        Violations(
          rule: check.rule,
          offenders: check.offenders.filter { offender in
            !contains(offender.affectedPath ?? offender.location.filePath)
          },
          checkedCount: check.checkedCount
        )
      },
      warnings: findings.warnings
    )
  }

  private func contains(_ filePath: String) -> Bool {
    let path = LexicalFilePath(filePath)
    return directories.contains { $0.contains(path) }
  }
}
