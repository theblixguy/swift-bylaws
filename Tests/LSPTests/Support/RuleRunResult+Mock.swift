import BylawsInterpreter
import BylawsSemantics
@testable import BylawsRunner

extension RuleRunResult {
  static func mock(
    rootPath: String,
    diagnosticAt path: String? = nil
  ) -> Self {
    let diagnostics = path.map {
      [Diagnostic(
        severity: .error,
        location: DeclarationLocation(
          filePath: $0,
          line: 1,
          column: 1,
          utf8Offset: 0
        ),
        message: "Class must be final"
      )]
    } ?? []
    return Self(
      rootPath: rootPath,
      reports: [],
      diagnostics: diagnostics,
      pathsThatDidNotParse: [],
      baselineEntries: [],
      outcome: .passed
    )
  }
}
