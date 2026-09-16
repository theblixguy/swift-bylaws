import BylawsCore
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner

@Suite("Rule result storage")
struct RuleResultStoreTests {
  @Test("Rule changes discard cached results")
  func changedRuleSource() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "let rules = true",
    ])
    let counts = InvocationCounts()
    let rule = incrementalRule(
      id: "classes",
      path: project.rootURL.path,
      counts: counts
    )
    let rulesPath = project.fileURL(for: "Bylaws.swift")
    let program = incrementalProgram(
      rules: [rule],
      sourcePath: rulesPath.path
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
    try "let changedRules = true".write(
      to: rulesPath,
      atomically: true,
      encoding: .utf8
    )
    var changed = initial
    changed.changedPaths = ["README.md"]
    _ = try await IncrementalRuleEvaluator.findings(
      of: [rule],
      program: program,
      configuration: changed
    )

    #expect(await counts.value(for: "classes") == 2)
  }

  @Test("Damaged cache reruns every rule")
  func damagedCache() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "let rules = true",
    ])
    let counts = InvocationCounts()
    let rule = incrementalRule(
      id: "classes",
      path: project.rootURL.path,
      counts: counts
    )
    let program = incrementalProgram(
      rules: [rule],
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    let cache = project.fileURL(for: "Cache")
    let initial = incrementalConfiguration(root: project.rootURL, cache: cache)

    _ = try await IncrementalRuleEvaluator.findings(
      of: [rule],
      program: program,
      configuration: initial
    )
    let cacheFile = try resultCacheFile(in: cache)
    try Data("damaged".utf8).write(to: cacheFile)
    var changed = initial
    changed.changedPaths = ["README.md"]
    _ = try await IncrementalRuleEvaluator.findings(
      of: [rule],
      program: program,
      configuration: changed
    )

    #expect(await counts.value(for: "classes") == 2)
  }

  @Test("Updates remove the previous result file before evaluation")
  func removesPersistedResults() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "let rules = true",
    ])
    let counts = InvocationCounts()
    let rule = incrementalRule(
      id: "classes",
      path: project.rootURL.path,
      counts: counts
    )
    let program = incrementalProgram(
      rules: [rule],
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    let cache = project.fileURL(for: "Cache")
    let configuration = incrementalConfiguration(
      root: project.rootURL,
      cache: cache
    )
    _ = try await IncrementalRuleEvaluator.findings(
      of: [rule],
      program: program,
      configuration: configuration
    )
    let cacheFile = try resultCacheFile(in: cache)
    let store = try #require(RuleResultStore.opening(
      program: program,
      configuration: configuration
    ))

    try store.removePersistedEntries()

    #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
  }

  @Test("Symbolic result files stop incremental evaluation")
  func rejectsSymbolicResultFile() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "let rules = true",
    ])
    let counts = InvocationCounts()
    let rule = incrementalRule(
      id: "classes",
      path: project.rootURL.path,
      counts: counts
    )
    let program = incrementalProgram(
      rules: [rule],
      sourcePath: project.fileURL(for: "Bylaws.swift").path
    )
    let cache = project.fileURL(for: "Cache")
    var configuration = incrementalConfiguration(
      root: project.rootURL,
      cache: cache
    )
    _ = try await IncrementalRuleEvaluator.findings(
      of: [rule],
      program: program,
      configuration: configuration
    )
    let cacheFile = try resultCacheFile(in: cache)
    let target = project.fileURL(for: "target.json")
    let targetData = Data("keep this".utf8)
    try targetData.write(to: target)
    try FileManager.default.removeItem(at: cacheFile)
    try FileManager.default.createSymbolicLink(
      at: cacheFile,
      withDestinationURL: target
    )
    configuration.changedPaths = ["README.md"]

    do {
      _ = try await IncrementalRuleEvaluator.findings(
        of: [rule],
        program: program,
        configuration: configuration
      )
      Issue.record("Incremental evaluation did not stop")
    } catch let .cache(error) {
      guard case let .entryIsSymbolicLink(path) = error else {
        Issue.record("Incremental evaluation returned \(error)")
        return
      }
      #expect(
        URL(fileURLWithPath: path).resolvingSymlinksInPath()
          == cacheFile.resolvingSymlinksInPath()
      )
    } catch {
      Issue.record("Incremental evaluation returned \(error)")
    }
    #expect(try Data(contentsOf: target) == targetData)
  }
}
