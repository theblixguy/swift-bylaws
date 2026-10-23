import BylawsCore
import BylawsPaths
import BylawsSemantics

struct ExcludedSubtrees: Sendable {
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
        check.filteringOffenders { offender in
          !contains(offender.affectedPath ?? offender.location.filePath)
        }
      },
      warnings: findings.warnings
    )
  }

  func contains(_ filePath: String) -> Bool {
    let path = LexicalFilePath(filePath)
    return directories.contains { $0.contains(path) }
  }
}
