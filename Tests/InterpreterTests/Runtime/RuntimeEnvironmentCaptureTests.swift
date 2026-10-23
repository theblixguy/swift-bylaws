import BylawsCore
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Runtime environment source capture")
struct RuntimeEnvironmentCaptureTests {
  @Test(
    "Warm rule captures inputs for sequential callers",
    arguments: [false, true]
  )
  func sequentialCallers(ruleArray: Bool) async throws {
    let project = try makeProject(ruleArray: ruleArray)
    let rule = try await warmRule(in: project)
    let first = try await capture(rule)
    let second = try await capture(rule)
    let dependencyPath = project.fileURL(for: "Inputs/Dependency.swift").path

    for (_, records) in [first, second] {
      #expect(records.flatMap(\.inputs).map(\.path).contains(dependencyPath))
      try await SourceCapture.validate(records)
    }
    #expect(Set(first.records) == Set(second.records))
  }

  @Test(
    "Warm rule captures inputs for concurrent callers",
    arguments: [false, true]
  )
  func concurrentCallers(ruleArray: Bool) async throws {
    let project = try makeProject(ruleArray: ruleArray)
    let rule = try await warmRule(in: project)
    async let first = capture(rule)
    async let second = capture(rule)
    let results = try await [first, second]
    let dependencyPath = project.fileURL(for: "Inputs/Dependency.swift").path

    try #require(results.count == 2)
    for (_, records) in results {
      #expect(records.flatMap(\.inputs).map(\.path).contains(dependencyPath))
      try await SourceCapture.validate(records)
    }
    #expect(Set(results[0].records) == Set(results[1].records))
  }

  @Test(
    "Replayed capture rejects changed dependency content or inventory",
    arguments: [false, true], ["Inputs/Dependency.swift", "Inputs/Added.swift"]
  )
  func changedDependency(ruleArray: Bool, changedPath: String) async throws {
    let project = try makeProject(ruleArray: ruleArray)
    let rule = try await warmRule(in: project)
    try project.write("struct ChangedDependency {}", to: changedPath)

    let (findings, records) = try await capture(rule)
    let edits = findings.violations.fixes.compactMap(\.self).flatMap(\.edits)
    #expect(edits.map(\.source.filePath) == [
      project.fileURL(for: "Sources/Main.swift").path,
    ])
    #expect(edits.map(\.replacement) == ["Updated"])
    #expect(records.flatMap(\.inputs).map(\.path).contains(
      project.fileURL(for: "Inputs/Dependency.swift").path
    ))
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test(
    "Prepared and unsaved sources retain lint results and reject capture",
    arguments: [false, true], [false, true]
  )
  func alternateSources(preparedSources: Bool, ruleArray: Bool) async throws {
    let ruleSource = """
    Rule("classes") {
      classes.violations(of: .isFinal).withFix { context in
        try context.offender.nameSource.replacement(with: "Updated")
      }
    }
    """
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: .v6)
      let classes = try await app.classes
      \(ruleArray ? "let rules = [\(ruleSource)]" : ruleSource)
      """,
      "Sources/Model.swift": "class Saved {}",
    ])
    let sourcePath = project.fileURL(for: "Sources/Model.swift").path
    let editedSource = "class Edited {}"
    let prepared: PreparedSources? = if preparedSources {
      try PreparedSources(files: [
        try FileCollector.collect(source: editedSource, path: sourcePath),
      ])
    } else {
      nil
    }
    let loading = CodebaseLoading(
      parseCachePolicy: .disabled,
      overlay: preparedSources ? .empty :
        SourceOverlay([sourcePath: editedSource]),
      preparedSources: prepared
    )
    let program = await SourceCapture.$collector.withValue(nil) {
      await RuleProgram.loaded(
        fromFiles: [LexicalFilePath(project.fileURL(for: "Bylaws.swift").path)],
        codebaseLoading: loading,
        indexProvider: nil,
        packageModuleIndex: nil
      )
    }
    try program.requireNoDiagnostics()
    let rule = try #require(program.rules.first)
    let findings = try await SourceCapture.$collector.withValue(nil) {
      try await rule.findings()
    }
    #expect(findings.violations.offenders.map(\.name) == ["Edited"])
    #expect(findings.violations.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.source.text) == ["Edited"])
    #expect(try String(contentsOfFile: sourcePath, encoding: .utf8) ==
      "class Saved {}")

    let collector = SourceCapture.Collector()
    await #expect {
      try await SourceCapture.$collector.withValue(collector) {
        try await rule.findings()
      }
    } throws: { error in
      guard let ruleError = error as? RuleError,
            case let .other(cause) = ruleError.cause,
            let failure = cause as? RuntimeError else { return false }
      return failure.message.contains("prepared or unsaved sources")
    }
    let records = await collector.captured
    #expect(records.contains { $0.unavailableReason != nil })
    #expect(records.flatMap(\.inputs).isEmpty)
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test("Failed environment replays failure markers and retries")
  func failedEnvironment() async throws {
    let project = try TemporaryProject(files: [
      "Sources/Broken.swift": "class {",
      "Inputs/Dependency.swift": "struct Dependency {}",
    ])
    let parsed = RulesFileParser.parse(
      source: """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: .v6)
      let inputs = Codebase(including: ["Inputs/**"], swiftLanguageMode: .v6)
      let dependencyCount = try await inputs.files.count
      let count = try await app.classes.count
      """,
      path: project.fileURL(for: "Bylaws.swift").path
    )
    try #require(parsed.diagnostics.isEmpty)
    let context = RuntimeProgramContext(file: parsed, indexProvider: nil)
    await #expect(throws: RuntimeError.self) {
      try await SourceCapture.$collector.withValue(nil) {
        try await context.resolvedEnvironment()
      }
    }
    let collectors = [SourceCapture.Collector(), SourceCapture.Collector()]
    await withTaskGroup(of: Void.self) { group in
      for collector in collectors {
        group.addTask {
          await #expect {
            try await SourceCapture.$collector.withValue(collector) {
              try await context.resolvedEnvironment()
            }
          } throws: { error in
            (error as? RuntimeError)?.parseDiagnostics?.isEmpty == false
          }
        }
      }
    }
    for collector in collectors {
      let records = await collector.captured
      #expect(records.contains { $0.unavailableReason != nil })
      #expect(records.flatMap(\.inputs).map(\.path).contains(
        project.fileURL(for: "Inputs/Dependency.swift").path
      ))
      await #expect(throws: CaptureError.self) {
        try await SourceCapture.validate(records)
      }
    }

    try project.write("class Recovered {}", to: "Sources/Broken.swift")
    let recovered = SourceCapture.Collector()
    let environment = try await SourceCapture.$collector.withValue(recovered) {
      try await context.resolvedEnvironment()
    }
    guard case let .integer(count)? = environment["count"] else {
      Issue.record("Recovered environment must contain class count")
      return
    }
    #expect(count == 1)
    let records = await recovered.captured
    #expect(!records.isEmpty)
    #expect(records.allSatisfy { $0.unavailableReason == nil })
    try await SourceCapture.validate(records)
  }

  private func makeProject(ruleArray: Bool) throws -> TemporaryProject {
    let rule = """
    Rule("dependency") {
      if dependencyCount == 1 {
        try await app.classes.violations(of: .isFinal).withFix { context in
          try context.offender.nameSource.replacement(with: "Updated")
        }
      }
    }
    """
    return try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"], swiftLanguageMode: .v6)
      let inputs = Codebase(including: ["Inputs/**"], swiftLanguageMode: .v6)
      let dependencyCount = try await inputs.files.count
      \(ruleArray ? "let rules = [\(rule)]" : rule)
      """,
      "Sources/Main.swift": "class Main {}",
      "Inputs/Dependency.swift": "struct Dependency {}",
    ])
  }

  private func warmRule(in project: TemporaryProject) async throws -> Rule {
    let program = try await SourceCapture.$collector.withValue(nil) {
      try await loadedProgram(in: project, rulesFile: "Bylaws.swift")
    }
    let rule = try #require(program.rules.first)
    let findings = try await SourceCapture.$collector.withValue(nil) {
      try await rule.findings()
    }
    #expect(findings.violations.offenders.map(\.name) == ["Main"])
    return rule
  }

  private func capture(_ rule: Rule) async throws
    -> (findings: Rule.Findings, records: [SourceCapture.Record])
  {
    let collector = SourceCapture.Collector()
    let findings = try await SourceCapture.$collector.withValue(collector) {
      try await rule.findings()
    }
    return (findings, await collector.captured)
  }
}
