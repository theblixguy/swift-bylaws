import BylawsInterpreter
import BylawsRunner
import BylawsSemantics
@testable import bylaws_cli

func render(
  reports: [RuleReport],
  diagnostics: [Diagnostic] = [],
  format: OutputFormat,
  quiet: Bool,
  rootPath: String = ""
) throws -> String {
  try ReportRenderer.render(
    ReportDocument(reports: reports, diagnostics: diagnostics),
    format: format,
    quiet: quiet,
    rootPath: rootPath
  )
}

func rulesFileLocation() -> DeclarationLocation {
  DeclarationLocation(
    filePath: "/project/Bylaws.swift",
    line: 4,
    column: 1,
    utf8Offset: 20
  )
}
