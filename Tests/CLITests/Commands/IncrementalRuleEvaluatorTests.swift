import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner

@Suite("Incremental rule evaluation")
struct IncrementalRuleEvaluatorTests {
  @Test("Unchanged dependencies reuse cached results")
  func reusesUnchangedResults() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "rules",
      "Sources/First/First.swift": "final class First {}",
      "Sources/Second/Second.swift": "final class Second {}",
    ])
    let counts = InvocationCounts()
    let first = incrementalRule(
      id: "first",
      path: project.fileURL(for: "Sources/First").path,
      counts: counts
    )
    let second = incrementalRule(
      id: "second",
      path: project.fileURL(for: "Sources/Second").path,
      counts: counts
    )
    let program = incrementalProgram(
      rules: [first, second],
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    let cache = project.fileURL(for: "Cache")
    let initial = incrementalConfiguration(root: project.rootURL, cache: cache)

    _ = try await IncrementalRuleEvaluator.findings(
      of: [first, second],
      program: program,
      configuration: initial
    )
    var changed = initial
    changed.changedPaths = ["Sources/First/First.swift"]
    _ = try await IncrementalRuleEvaluator.findings(
      of: [first, second],
      program: program,
      configuration: changed
    )

    #expect(await counts.value(for: "first") == 2)
    #expect(await counts.value(for: "second") == 1)
  }

  @Test("Missing results run every rule")
  func missingResults() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "rules",
      "Sources/First/First.swift": "final class First {}",
      "Sources/Second/Second.swift": "final class Second {}",
    ])
    let counts = InvocationCounts()
    let rules = [
      incrementalRule(
        id: "first",
        path: project.fileURL(for: "Sources/First").path,
        counts: counts
      ),
      incrementalRule(
        id: "second",
        path: project.fileURL(for: "Sources/Second").path,
        counts: counts
      ),
    ]
    let program = incrementalProgram(
      rules: rules,
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    var configuration = incrementalConfiguration(
      root: project.rootURL,
      cache: project.fileURL(for: "Cache")
    )
    configuration.changedPaths = ["Sources/First/First.swift"]

    _ = try await IncrementalRuleEvaluator.findings(
      of: rules,
      program: program,
      configuration: configuration
    )

    #expect(await counts.value(for: "first") == 1)
    #expect(await counts.value(for: "second") == 1)
  }

  @Test("Changed paths discard skipped rule results")
  func skippedRule() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "rules",
      "Sources/First/First.swift": "final class First {}",
      "Sources/Second/Second.swift": "final class Second {}",
    ])
    let counts = InvocationCounts()
    let first = incrementalRule(
      id: "first",
      path: project.fileURL(for: "Sources/First").path,
      counts: counts
    )
    let second = incrementalRule(
      id: "second",
      path: project.fileURL(for: "Sources/Second").path,
      counts: counts
    )
    let program = incrementalProgram(
      rules: [first, second],
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    let cache = project.fileURL(for: "Cache")
    let initial = incrementalConfiguration(root: project.rootURL, cache: cache)

    _ = try await IncrementalRuleEvaluator.findings(
      of: [first, second],
      program: program,
      configuration: initial
    )
    var secondChanged = initial
    secondChanged.changedPaths = ["Sources/Second/Second.swift"]
    _ = try await IncrementalRuleEvaluator.findings(
      of: [first],
      program: program,
      configuration: secondChanged
    )
    var unrelatedChange = initial
    unrelatedChange.changedPaths = ["README.md"]
    _ = try await IncrementalRuleEvaluator.findings(
      of: [second],
      program: program,
      configuration: unrelatedChange
    )

    #expect(await counts.value(for: "first") == 1)
    #expect(await counts.value(for: "second") == 2)
  }

  @Test("Overrides cache independently")
  func overrides() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "rules",
      "Sources/First/First.swift": "final class First {}",
      "Sources/Second/Second.swift": "final class Second {}",
    ])
    let counts = InvocationCounts()
    let first = incrementalRule(
      id: "classes",
      path: project.fileURL(for: "Sources/First").path,
      counts: counts,
      countKey: "first",
      location: .init(filePath: "Bylaws.swift", line: 1, column: 1)
    )
    let second = incrementalRule(
      id: "classes",
      path: project.fileURL(for: "Sources/Second").path,
      counts: counts,
      countKey: "second",
      location: .init(filePath: "Module/Bylaws.swift", line: 1, column: 1)
    )
    let program = incrementalProgram(
      rules: [first, second],
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    let initial = incrementalConfiguration(
      root: project.rootURL,
      cache: project.fileURL(for: "Cache")
    )

    _ = try await IncrementalRuleEvaluator.findings(
      of: [first, second],
      program: program,
      configuration: initial
    )
    var changed = initial
    changed.changedPaths = ["Sources/First/First.swift"]
    _ = try await IncrementalRuleEvaluator.findings(
      of: [first, second],
      program: program,
      configuration: changed
    )

    #expect(await counts.value(for: "first") == 2)
    #expect(await counts.value(for: "second") == 1)
  }

  @Test("Untracked dependencies run again")
  func untrackedDependencies() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "let rules = true",
    ])
    let counts = InvocationCounts()
    let rule = Rule("index", "Index available") {
      await counts.increment("index")
      await RuleDependencyTracking.recordUntrackedDependency()
      return Violations<Offender>(
        rule: "find an index",
        offenders: [],
        checkedCount: 1
      )
    }
    let program = incrementalProgram(
      rules: [rule],
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    let initial = incrementalConfiguration(
      root: project.rootURL,
      cache: project.fileURL(for: "Cache")
    )

    _ = try await IncrementalRuleEvaluator.findings(
      of: [rule],
      program: program,
      configuration: initial
    )
    var changed = initial
    changed.changedPaths = ["README.md"]
    _ = try await IncrementalRuleEvaluator.findings(
      of: [rule],
      program: program,
      configuration: changed
    )

    #expect(await counts.value(for: "index") == 2)
  }
}
