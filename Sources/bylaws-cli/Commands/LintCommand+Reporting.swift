import ArgumentParser
import BylawsInterpreter
import BylawsRunner
import BylawsSemantics
import Foundation

extension LintCommand {
  func writeReport(
    _ document: ReportDocument,
    rootPath: String,
    quiet: Bool
  ) throws {
    let rendered = try ReportRenderer.render(
      document, format: format, quiet: quiet, rootPath: rootPath
    )
    guard let output else {
      if !rendered.isEmpty {
        print(rendered)
      }
      return
    }

    let diagnostics = try ReportRenderer.render(
      document, format: .xcode, quiet: true, rootPath: rootPath
    )
    if !diagnostics.isEmpty {
      try FileHandle.standardError
        .write(contentsOf: Data((diagnostics + "\n").utf8))
    }
    do {
      let content = rendered.isEmpty ? "" : rendered + "\n"
      try content.write(toFile: output, atomically: true, encoding: .utf8)
    } catch {
      let message = "error: cannot write report to '\(output)': \(error.reportableDescription). "
        + "Check that the directory exists and permits writing.\n"
      try FileHandle.standardError.write(contentsOf: Data(message.utf8))
      throw ExitCode(2)
    }
  }

  func reportError(_ message: String, rootPath: String) throws {
    try writeReport(
      ReportDocument(reports: [], diagnostics: [
        Diagnostic(
          severity: .error,
          location: DeclarationLocation.rulesFile(atRoot: rootPath),
          message: message
        ),
      ]),
      rootPath: rootPath,
      quiet: true
    )
  }
}
