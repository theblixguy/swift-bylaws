import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

func correctedSource(
  applying fix: SourceFix,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> String {
  let first = try #require(fix.edits.first, sourceLocation: sourceLocation)
  return try first.source.file.replacement(applying: fix.edits).replacement
}

func correctionProject(
  declarations: String = "",
  ruleBody: String
) throws -> TemporaryProject {
  try TemporaryProject(files: [
    "Package.swift": "",
    "ProjectRules.swift": """
    import Bylaws
    let app = Codebase(including: ["Sources/**"])
    \(declarations)
    let rules = [Rule("types") {
      \(ruleBody)
    }]
    """,
    "Sources/Model.swift": "class Model { var stored = 1 }",
  ])
}

func expectCorrectionRejection(
  in project: TemporaryProject,
  containing message: String,
  atLine line: Int,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  let program = await RuleProgram
    .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])

  #expect(program.rules.isEmpty, sourceLocation: sourceLocation)
  #expect(
    program.errors.contains {
      $0.message.contains(message)
        && $0.location.filePath == project.fileURL(for: "ProjectRules.swift")
        .path
        && $0.location.line == line
    },
    "\(program.errors.map { "\($0.location.line): \($0.message)" })",
    sourceLocation: sourceLocation
  )
}
