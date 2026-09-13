import BylawsCore
package import BylawsInterpreter
package import BylawsSemantics

package struct ReportDocument {
  package struct RuleEntry {
    package let id: String
    package let name: String
    package let hint: String?
    package let level: Level
  }

  package struct Event {
    package enum Category: Equatable {
      case violation
      case warning
      case diagnostic
    }

    package let category: Category
    package let level: Level
    package let message: String
    package let hint: String?
    package let location: DeclarationLocation
    package let ruleID: String?
    package let ruleIndex: Int?

    package var messageWithRuleID: String {
      message + (ruleID.map { " [\($0)]" } ?? "") + hintClause
    }

    package var messageWithoutRuleID: String {
      message + hintClause
    }

    private var hintClause: String {
      hint.map { " (\($0))" } ?? ""
    }
  }

  package enum Level: Equatable {
    case error
    case warning
    case notice

    init(_ severity: Diagnostic.Severity) {
      switch severity {
      case .error: self = .error
      case .warning: self = .warning
      case .notice: self = .notice
      }
    }
  }

  package let rules: [RuleEntry]
  package let events: [Event]
  package let reportCount: Int
  package let violationCount: Int

  package init(reports: [RuleReport], diagnostics: [Diagnostic]) {
    var rules: [RuleEntry] = []
    var indexByID: [String: Int] = [:]
    var events = diagnostics.map { diagnostic in
      Event(
        category: .diagnostic,
        level: Level(diagnostic.severity),
        message: diagnostic.message,
        hint: diagnostic.hint,
        location: diagnostic.location,
        ruleID: nil,
        ruleIndex: nil
      )
    }

    for report in reports {
      let id = report.id.rawValue
      let level: Level = report.enforcement == .advisory ? .warning : .error
      let ruleIndex: Int
      if let known = indexByID[id] {
        ruleIndex = known
      } else {
        ruleIndex = rules.count
        indexByID[id] = ruleIndex
        rules.append(
          RuleEntry(
            id: id,
            name: report.name,
            hint: report.hint,
            level: level
          )
        )
      }

      for offender in report.violations.offenders {
        events.append(
          Event(
            category: .violation,
            level: level,
            message: "\(offender.description) violates '\(offender.requirement ?? report.name)'",
            hint: report.hint,
            location: offender.location,
            ruleID: id,
            ruleIndex: ruleIndex
          )
        )
      }
      for warning in report.warnings {
        events.append(
          Event(
            category: .warning,
            level: .warning,
            message: "\(report.name): \(warning.message)",
            hint: nil,
            location: warning.location,
            ruleID: id,
            ruleIndex: ruleIndex
          )
        )
      }
      if report.violations.checkedCount == 0, report.warnings.isEmpty {
        events.append(
          Event(
            category: .warning,
            level: .warning,
            message: "\(report.name): the query matched no declarations",
            hint: nil,
            location: report.location,
            ruleID: id,
            ruleIndex: ruleIndex
          )
        )
      }
    }

    self.rules = rules
    self.events = events
    reportCount = reports.count
    violationCount = reports.reduce(0) { $0 + $1.violations.count }
  }
}
