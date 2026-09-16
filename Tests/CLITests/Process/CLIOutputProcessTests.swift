import Foundation
import Testing

@Suite("Bylaws process output")
struct CLIOutputProcessTests {
  @Test("--report-path limits output and exit status to one file")
  func reportPath() throws {
    let project = try CLIProcessProject(
      source: "class Included {}",
      rules: CLIProcessMock.finalClassesRule,
      extraFiles: [
        "Sources/App/Other.swift": "class Excluded {}",
      ]
    )

    let included = try project.run(
      "--report-path", "Sources/App/App.swift"
    )
    let unrelated = try project.run(
      "--report-path", "Sources/App/Missing.swift"
    )

    #expect(included.status == 1)
    #expect(included.standardOutput.contains("Included"))
    #expect(!included.standardOutput.contains("Excluded"))
    #expect(unrelated.status == 0)
    #expect(unrelated.standardOutput.contains("0 violations"))
  }

  @Test("--format json writes a JSON report")
  func jsonFormat() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run("--format", "json")
    let value = try #require(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8))
        as? [String: Any]
    )

    #expect(result.status == 1)
    #expect(value["schemaVersion"] as? Int == 1)
    #expect(
      (value["events"] as? [[String: Any]])?.first?["kind"] as? String
        == "violation"
    )
  }

  @Test("--cache-path selects the parse cache directory")
  func explicitCachePath() throws {
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let cache = project.root.appendingPathComponent("ParseCache")

    let result = try project.run("--cache-path", cache.path)
    let entries =
      FileManager.default.enumerator(atPath: cache.path)?
        .compactMap { $0 as? String } ?? []

    #expect(result.status == 0)
    #expect(entries.contains { $0.hasSuffix(".bin") })
  }

  @Test("--cache-size applies a lower target on the next run")
  func reducedCacheSize() throws {
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let cache = project.root.appendingPathComponent("ParseCache")
    let small = try project.run(
      "--cache-path",
      cache.path,
      "--cache-size",
      "1B"
    )
    #expect(small.status == 0)
    let larger = try project.run(
      "--cache-path",
      cache.path,
      "--cache-size",
      "1GB"
    )
    #expect(larger.status == 0)

    let reduced = try project.run(
      "--cache-path",
      cache.path,
      "--cache-size",
      "1B"
    )
    let entries = FileManager.default.enumerator(atPath: cache.path)?
      .compactMap { $0 as? String } ?? []

    #expect(reduced.status == 0)
    #expect(!entries.contains { $0.hasSuffix(".bin") })
  }

  @Test("Zero size disables cache writes")
  func zeroCacheSize() throws {
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let cache = project.root.appendingPathComponent("ParseCache")

    let result = try project.run(
      "--cache-path",
      cache.path,
      "--cache-size",
      "0"
    )

    #expect(result.status == 0)
    #expect(!FileManager.default.fileExists(atPath: cache.path))
  }
}
