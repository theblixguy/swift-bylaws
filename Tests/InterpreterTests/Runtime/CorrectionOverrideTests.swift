import BylawsCore
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Imported rule correction overrides")
struct CorrectionOverrideTests {
  @Test("Declared rules skip parent fix closures for child offenders")
  func importedHelper() async throws {
    let project = try project(rootRules: """
    import Bylaws
    import SharedRules
    Rule("names") { try await corrected("ParentFixed") }
    """)
    let program = await RuleProgram.discovered(
      atRoot: LexicalFilePath(project.rootURL.path),
      parseCachePolicy: .disabled,
      packageModuleIndex: try PackageModuleIndex(modules: [
        .init(
          name: "SharedRules",
          sourceFiles: [project.fileURL(for: "Rules/SharedRules.swift").path],
          dependencies: ["Bylaws"]
        ),
      ])
    )
    try program.requireNoDiagnostics()
    try #require(program.rules.count == 2)
    let parent = try #require(program.rules.first {
      $0.origin == Rule.Origin(
        filePath: project.fileURL(for: "Bylaws.swift").path, ruleID: "names"
      )
    })
    let child = try #require(program.rules.first {
      $0.origin == Rule.Origin(
        filePath: project.fileURL(for: "Sources/Child/Bylaws.swift").path,
        ruleID: "names"
      )
    })

    try check(
      await parent.findings(),
      expected: ["Root": "ParentFixed", "Sibling": "ParentFixed"],
      checkedCount: 3,
      in: project
    )
    try check(
      await child.findings(), expected: ["Child": "ChildFixed"],
      checkedCount: 1, in: project
    )
  }

  @Test(
    "Runtime arrays invoke fixes within rule scope",
    arguments: [false, true]
  )
  func runtimeArray(excludingChild: Bool) async throws {
    let project = try project(rootRules: "import SharedRules")
    let helperPath = project.fileURL(for: "Rules/SharedRules.swift").path
    var helper = RulesFileParser.parse(
      source: try String(contentsOfFile: helperPath, encoding: .utf8),
      path: helperPath
    )
    RuntimeProgramResolver.resolve(&helper)
    try #require(helper.diagnostics.isEmpty)
    let context = RuntimeProgramContext(file: helper, indexProvider: nil)
    let values = try await context.resolvedRules()
    let value = try #require(values.first)
    #expect(value.location.filePath == helperPath)
    let consumer = ParsedRulesFile(
      path: project.fileURL(for: "Bylaws.swift").path,
      directory: project.rootURL.path
    )
    #expect(consumer.codebases.isEmpty)
    let rule = RuntimeProgramCompiler.compile(
      value, in: consumer,
      excludingSubtrees: excludingChild ? ["Sources/Child"] : []
    )

    if excludingChild {
      try check(
        await rule.findings(),
        expected: ["Root": "ParentFixed", "Sibling": "ParentFixed"],
        checkedCount: 3,
        in: project
      )
    } else {
      await #expect {
        try await rule.findings()
      } throws: { error in
        guard let ruleError = error as? RuleError,
              case let .other(cause) = ruleError.cause,
              let failure = cause as? RuntimeError else { return false }
        return failure.message
          .contains("Source matches must contain one match, found 0")
          && failure.location.filePath == helperPath
      }
    }
  }

  private func project(rootRules: String) throws -> TemporaryProject {
    try TemporaryProject(files: [
      "Bylaws.swift": rootRules,
      "Rules/SharedRules.swift": """
      import Bylaws
      let app = Codebase(
        root: .directory(".."),
        including: ["Sources/**"],
        swiftLanguageMode: .v6
      )
      public func corrected(_ replacement: String) async throws -> Violations<Class> {
        return try await app.classes.violations(of: .isFinal).withFix { context in
          let name = try context.offender.nameSource
          let match = try name.matches(of: /Root|Sibling/).only()
          match.replacement(with: replacement)
        }
      }
      public let helperRules: [Rule] = [
        Rule("names") { try await corrected("ParentFixed") }
      ]
      """,
      "Sources/Child/Bylaws.swift": """
      import Bylaws
      let child = Codebase(including: ["**"], swiftLanguageMode: .v6)
      Override("names", reason: "Child names differ") {
        try await child.classes.violations(of: .isFinal).withFix { context in
          try context.offender.nameSource.replacement(with: "ChildFixed")
        }
      }
      """,
      "Sources/Root.swift": "class Root {}",
      "Sources/Child/Child.swift": "class Child {}",
      "Sources/ChildKit/Sibling.swift": "class Sibling {}",
    ])
  }

  private func check(
    _ findings: Rule.Findings,
    expected: [String: String],
    checkedCount: Int,
    in project: TemporaryProject
  ) throws {
    let violations = findings.violations
    #expect(violations.checkedCount == checkedCount)
    #expect(violations.offenders.compactMap(\.name).sorted() == expected.keys
      .sorted())
    try #require(violations.fixes.count == expected.count)
    let paths = [
      "Root": "Sources/Root.swift",
      "Child": "Sources/Child/Child.swift",
      "Sibling": "Sources/ChildKit/Sibling.swift",
    ]
    for (offender, fix) in zip(violations.offenders, violations.fixes) {
      let name = try #require(offender.name)
      let fix = try #require(fix)
      try #require(fix.edits.count == 1)
      let edit = try #require(fix.edits.first)
      let path = try #require(paths[name])
      #expect(edit.source.text == name)
      #expect(edit.source.filePath == project.fileURL(for: path).path)
      #expect(edit.replacement == expected[name])
    }
  }
}
