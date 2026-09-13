import BylawsCore
import BylawsPaths
import BylawsSemantics

enum RuleInspectionPrinter {
  static func print(
    _ inspection: Rule.Inspection,
    rule: Rule,
    rootPath: String
  ) {
    Swift.print("\(rule.id): \(rule.name)")
    Swift.print("  Rule file: \(position(rule.location, rootPath: rootPath))")
    Swift
      .print(
        "Source include and exclude patterns apply before the first selection."
      )
    if inspection.selections.isEmpty {
      Swift.print("  This rule recorded no Bylaws selection queries.")
    }
    for step in inspection.selections {
      Swift.print("  \(step.queryDescription)")
      Swift.print("    Selected: \(step.selected.count)")
      for element in step.selected {
        Swift.print("      \(label(element, rootPath: rootPath))")
      }
      Swift.print("    Excluded: \(step.excluded.count)")
      for element in step.excluded {
        Swift.print("      \(label(element, rootPath: rootPath))")
      }
    }
    let findings = inspection.findings
    Swift.print("  Checked: \(findings.violations.checkedCount)")
    Swift.print("  Violations: \(findings.violations.count)")
    for offender in findings.violations.offenders {
      Swift
        .print(
          "    \(position(offender.location, rootPath: rootPath)) \(offender.description)"
        )
    }
    for warning in findings.warnings {
      Swift.print("  Warning: \(warning.message)")
    }
  }

  private static func label(
    _ element: SelectionInspection.Element,
    rootPath: String
  ) -> String {
    "\(position(element.location, rootPath: rootPath)) \(element.name ?? element.description)"
  }

  private static func position(
    _ location: DeclarationLocation,
    rootPath: String
  ) -> String {
    let path = LexicalFilePath(location.filePath)
    let relative = path.relative(to: LexicalFilePath(rootPath))?.string ?? path
      .string
    return "\(relative):\(location.line):\(location.column)"
  }
}
