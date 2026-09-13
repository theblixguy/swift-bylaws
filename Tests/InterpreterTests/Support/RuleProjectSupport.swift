import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

extension RuleProgram {
  func requireNoDiagnostics(
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    try #require(
      diagnostics.isEmpty,
      "\(diagnostics.map(\.message))",
      sourceLocation: sourceLocation
    )
  }
}

func rulesProject(
  rules: String,
  sources: [String: String]
) throws -> TemporaryProject {
  var files = sources
  files["Package.swift"] = ""
  files["ProjectRules.swift"] = """
  import Bylaws

  let app = Codebase(root: .automatic(), including: ["Sources/**"])

  let projectRules: [Rule] = [
  \(rules)
  ]
  """
  return try TemporaryProject(files: files)
}

func loadedProgram(
  in project: TemporaryProject,
  rulesFile: String = "ProjectRules.swift",
  sourceLocation: SourceLocation = #_sourceLocation
) async throws -> RuleProgram {
  let program = await RuleProgram.loaded(
    fromFiles: ["\(project.rootURL.path)/\(rulesFile)"]
  )
  try program.requireNoDiagnostics(sourceLocation: sourceLocation)
  return program
}

func offenderNames(
  ofFirstRuleIn project: TemporaryProject,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws -> [String?] {
  let program = try await loadedProgram(
    in: project,
    sourceLocation: sourceLocation
  )
  let rule = try #require(program.rules.first, sourceLocation: sourceLocation)
  return try await rule.violations().offenders.map(\.name)
}

let smallAndLargeClasses = """
class Small { func one() {} }
class Large { func one() {}; func two() {} }
"""

func discoveredProgram(
  in project: TemporaryProject,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws -> RuleProgram {
  let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
  try program.requireNoDiagnostics(sourceLocation: sourceLocation)
  return program
}

let finalClassRuleSource = """
let app = Codebase(including: ["**"])
Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
"""

func diagnostics(
  forRules source: String,
  sources: [String: String] = ["Sources/App/A.swift": "class A {}"]
) async throws -> (RuleProgram, TemporaryProject) {
  var files = sources
  files["Bylaws.swift"] = source
  let project = try TemporaryProject(files: files)
  return (await RuleProgram.discovered(atRoot: project.rootURL.path), project)
}

func expectDiagnostic(
  _ diagnostic: Diagnostic,
  messageContaining message: String,
  hintContaining hint: String?,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  #expect(
    diagnostic.message.contains(message),
    sourceLocation: sourceLocation
  )
  if let hint {
    #expect(
      try #require(diagnostic.hint, sourceLocation: sourceLocation)
        .contains(hint),
      sourceLocation: sourceLocation
    )
  }
}

func advisoryDocumentationProject() throws -> TemporaryProject {
  try TemporaryProject(files: [
    "Bylaws.swift": """
    let app = Codebase(including: ["Sources/**"])

    Rule("docs", "Public classes carry documentation", enforcement: .advisory) {
      app.classes.violations(of: .hasDocumentation)
    }
    """,
    "Sources/App/A.swift": "public class A {}",
  ])
}

func packageDependencyProject(
  rulesFile: String,
  rulesSource: String
) throws -> TemporaryProject {
  var files = [
    "Package.swift": """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
      name: "Example",
      targets: [
        .target(name: "App", dependencies: ["Unused"]),
        .target(name: "Domain"),
        .target(name: "Unused"),
      ]
    )
    """,
    "Sources/App/App.swift": "import Domain\nstruct App {}",
    "Sources/Domain/Domain.swift": "struct Domain {}",
    "Sources/Unused/Unused.swift": "struct Unused {}",
  ]
  files[rulesFile] = rulesSource
  return try TemporaryProject(files: files)
}

func expectPackageDependencyFindings(_ findings: Rule.Findings) {
  let offenderNames = findings.violations.offenders.map(\.name)
  #expect(offenderNames.count == 2)
  #expect(offenderNames.contains("Domain"))
  #expect(offenderNames.contains("App depends on Unused"))
  #expect(findings.warnings.isEmpty)
}

func readFailureDescription(at path: String) -> String {
  do {
    _ = try String(contentsOfFile: path, encoding: .utf8)
    Issue.record("the read unexpectedly succeeded")
    return ""
  } catch {
    return error.localizedDescription
  }
}
