import ArgumentParser
import BylawsCore
import BylawsInterpreter
import BylawsRunner
import BylawsSemantics

enum OutputFormat: String, ExpressibleByArgument {
  case xcode
  case github
  case json
  case sarif
}

enum ReportRenderer {
  static func render(
    _ document: ReportDocument,
    format: OutputFormat,
    quiet: Bool,
    rootPath: String = ""
  ) throws -> String {
    switch format {
    case .xcode: xcode(document: document, quiet: quiet)
    case .github: github(
        document: document,
        rootPath: rootPath
      )
    case .json: try JSONReport(document: document, rootPath: rootPath).rendered
    case .sarif: try SARIFLog(document: document, rootPath: rootPath).rendered
    }
  }

  private static func xcode(
    document: ReportDocument,
    quiet: Bool
  ) -> String {
    var lines = document.events.map { event in
      "\(event.location.filePath):\(event.location.line):"
        + "\(event.location.column): \(event.level.compilerName): "
        + xcodeMessage(event.messageWithRuleID)
    }
    lines += document.referencedRules.map { rule in
      "\(rule.location.filePath):\(rule.location.line):"
        + "\(rule.location.column): note: "
        + xcodeMessage("rule '\(rule.id)' is declared here")
    }
    if !quiet {
      let ruleCount = document.reportCount == 1
        ? "1 rule" : "\(document.reportCount) rules"
      let violationCount = document.violationCount == 1
        ? "1 violation" : "\(document.violationCount) violations"
      lines.append("Checked \(ruleCount): \(violationCount).")
    }
    return lines.joined(separator: "\n")
  }

  private static func xcodeMessage(_ text: String) -> String {
    text.replacing("\r\n", with: " ")
      .replacing("\r", with: " ")
      .replacing("\n", with: " ")
  }

  private static func github(
    document: ReportDocument,
    rootPath: String
  ) -> String {
    func path(of declaration: DeclarationLocation) -> String {
      let path = ReportPath.relative(declaration.filePath, to: rootPath)
        ?? declaration.filePath
      return escapedProperty(path)
    }

    var lines = document.events.map { event in
      "::\(event.level.reportName) file=\(path(of: event.location)),"
        + "line=\(event.location.line)::"
        + escapedMessage(event.messageWithRuleID)
    }
    lines += document.referencedRules.map { rule in
      "::notice file=\(path(of: rule.location)),line=\(rule.location.line)::"
        + escapedMessage("rule '\(rule.id)' is declared here")
    }
    return lines.joined(separator: "\n")
  }

  private static func escapedMessage(_ text: String) -> String {
    text.replacing("%", with: "%25")
      .replacing("\r", with: "%0D")
      .replacing("\n", with: "%0A")
  }

  private static func escapedProperty(_ text: String) -> String {
    escapedMessage(text)
      .replacing(":", with: "%3A")
      .replacing(",", with: "%2C")
  }
}
