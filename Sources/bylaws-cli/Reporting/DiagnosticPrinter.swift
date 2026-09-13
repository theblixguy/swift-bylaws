import BylawsInterpreter
import BylawsRunner
import BylawsSemantics
import Foundation

enum DiagnosticPrinter {
  static func print(
    _ diagnostics: [Diagnostic],
    format: OutputFormat,
    rootPath: String
  ) throws {
    let output = try ReportRenderer.render(
      ReportDocument(reports: [], diagnostics: diagnostics),
      format: format,
      quiet: true,
      rootPath: rootPath
    )
    if !output.isEmpty {
      Swift.print(output)
    }
  }

  static func printError(
    _ message: String,
    rulesFileRoot: String,
    format: OutputFormat,
    renderRootPath: String? = nil
  ) throws {
    try print(
      [
        Diagnostic(
          severity: .error,
          location: DeclarationLocation.rulesFile(atRoot: rulesFileRoot),
          message: message
        ),
      ],
      format: format,
      rootPath: renderRootPath ?? rulesFileRoot
    )
  }

  static func printWriteFailure(
    _ error: some Error,
    writing target: String,
    rulesFileRoot: String,
    format: OutputFormat
  ) throws {
    try printError(
      "could not write \(target): \(error.reportableDescription)",
      rulesFileRoot: rulesFileRoot,
      format: format
    )
  }
}
