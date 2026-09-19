import BylawsRunner
import BylawsSemantics

struct JSONReport: Encodable {
  let schemaVersion = 1
  let rules: [Rule]
  let events: [Event]
  let summary: Summary

  struct Rule: Encodable {
    let id: String
    let name: String
    let hint: String?
    let level: String
    let path: String
    let line: Int
    let column: Int
  }

  struct Event: Encodable {
    enum Kind: String, Encodable {
      case violation
      case warning
      case diagnostic
    }

    let kind: Kind
    let level: String
    let message: String
    let hint: String?
    let path: String
    let line: Int
    let column: Int
    let ruleID: String?
  }

  struct Summary: Encodable {
    let checkedRules: Int
    let violations: Int
  }
}

extension JSONReport {
  init(document: ReportDocument, rootPath: String) {
    rules = document.rules.map { rule in
      Rule(
        id: rule.id,
        name: rule.name,
        hint: rule.hint,
        level: rule.level.reportName,
        path: Self.path(
          rule.location.filePath,
          relativeTo: rootPath
        ),
        line: rule.location.line,
        column: rule.location.column
      )
    }
    events = document.events.map { event in
      let kind: Event.Kind = switch event.category {
      case .violation: .violation
      case .warning: .warning
      case .diagnostic: .diagnostic
      }
      return Event(
        kind: kind,
        level: event.level.reportName,
        message: event.message,
        hint: event.hint,
        path: Self.path(
          event.location.filePath,
          relativeTo: rootPath
        ),
        line: event.location.line,
        column: event.location.column,
        ruleID: event.ruleID
      )
    }
    summary = Summary(
      checkedRules: document.reportCount,
      violations: document.violationCount
    )
  }

  var rendered: String {
    get throws {
      try renderReportJSON(self)
    }
  }

  private static func path(_ path: String, relativeTo rootPath: String)
    -> String
  {
    ReportPath.relative(path, to: rootPath) ?? path
  }
}
