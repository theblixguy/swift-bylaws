import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Bazel dependency graph")
struct BazelGraphTests {
  @Test("Empty query exports load", arguments: [
    "{}", #"{"results": []}"#, #"{"configurations": []}"#,
    #"{"results": null}"#,
  ])
  func emptyExport(json: String) async throws {
    #expect(try await graph(json: json).targets.isEmpty)
  }

  @Test(
    "Dependencies retain build configurations",
    arguments: ["debug", "release"]
  )
  func configurations(_ configuration: String) async throws {
    let graph = try await graph()
    let feature = try #require(graph.targets.first {
      $0.label == "//features:Orders" && $0.configuration?
        .checksum == configuration
    })
    let direct = graph.directTargetDependencies(of: feature)
    #expect(direct.map(\.label) == ["//services:Store"])
    #expect(direct.map(\.configuration?.checksum) == [configuration])

    let dependencies = graph.transitiveTargetDependencies(of: feature)
    let expected = if configuration == "debug" {
      ["//services:Store", "//storage:Database", "//storage:Database.swift"]
    } else {
      ["//services:Store", "//storage:Memory"]
    }
    #expect(dependencies.map(\.label) == expected)
    #expect(feature.ruleClass == "swift_library")
    #expect(feature.tags == ["feature"])
    #expect(feature.location.filePath == "/virtual/features/BUILD.bazel")
    #expect(feature.location.line == 8)
    #expect(feature.location.column == 3)
  }

  @Test("File targets have no build configuration")
  func sourceFile() async throws {
    let graph = try await graph()
    let file = try #require(graph.targets
      .first { $0.label == "//storage:Database.swift" })
    #expect(file.configuration == nil)
    #expect(file.ruleClass == nil)
    #expect(file.tags.isEmpty)
    #expect(graph.directTargetDependencies(of: file).isEmpty)
  }

  @Test("Missing source positions use the export path")
  func missingLocation() async throws {
    let graph = try await graph()
    let database = try #require(graph.targets
      .first { $0.label == "//storage:Database" })
    #expect(database.location.filePath == "/virtual/graph.json")
    #expect(database.location.line == 1)
  }

  @Test(
    "Graph exports load without parsing Swift files",
    arguments: [false, true]
  )
  func fileLoading(absolutePath: Bool) async throws {
    let project = try TemporaryProject(files: [
      "MODULE.bazel": "module(name = \"app\")",
      "graph.json": BazelGraphMock.json,
      "Broken.swift": "struct {",
    ])
    let codebase = Codebase(root: .directory(project.rootURL.path))
    let path = absolutePath ? project.fileURL(for: "graph.json").path : "graph.json"
    #expect(try await codebase.bazelGraph(from: path).targets.count == 7)
    try project.write(#"{"results": []}"#, to: "graph.json")
    #expect(try await codebase.bazelGraph(from: path).targets.isEmpty)
  }

  @Test("Missing exports report their path")
  func missingExport() async throws {
    let project = try TemporaryProject(files: [:])
    let codebase = Codebase(root: .directory(project.rootURL.path))
    await #expect {
      try await codebase.bazelGraph(from: "missing.json")
    } throws: { error in
      guard let error = error as? CodebaseError,
            case let .bazelGraph(path, _) = error else { return false }
      return path == project.fileURL(for: "missing.json").path
    }
  }

  @Test("Incomplete query data fails to load", arguments: [
    (json: #"{"target": []}"#, reason: "cquery JSON"),
    (json: #"{"unknown": 1}"#, reason: "cquery JSON"),
    (json: "not JSON", reason: "JSON"),
    (
      json: #"{"results":[{"configurationId":1,"target":{"type":"RULE","rule":{"name":"//:App","ruleClass":"swift_library"}}}]}"#,
      reason: "configuration 1"
    ),
    (
      json: #"{"results":[{"target":{"type":"RULE","rule":{"name":"//:App","ruleClass":"swift_library"}}}]}"#,
      reason: "configuration for '//:App'"
    ),
    (
      json: #"{"configurations":[{"id":1,"checksum":"debug"}],"results":[{"configurationId":1,"target":{"type":"RULE","rule":{"name":"//:App","ruleClass":"swift_library","ruleInput":["//:Core"]}}}]}"#,
      reason: "configured dependencies"
    ),
    (
      json: #"{"configurations":[{"id":1,"checksum":"debug"}],"results":[{"configurationId":1,"target":{"type":"RULE","rule":{"name":"//:App","ruleClass":"swift_library","configuredRuleInput":[{"label":"//:Core","configurationId":1}]}}}]}"#,
      reason: "omits dependency '//:Core'"
    ),
  ])
  func incompleteQuery(input: (json: String, reason: String)) async throws {
    await #expect {
      try await graph(json: input.json)
    } throws: { error in
      String(describing: error).contains(input.reason)
        && String(describing: error).contains("--transitions=lite")
    }
  }

  @Test("Repeated dependencies and cycles terminate")
  func repeatedDependencies() async throws {
    let json = BazelGraphMock.json.replacing(
      #""configuredRuleInput": [{"label": "//storage:Database", "configurationId": 1}]"#,
      with: #""configuredRuleInput": [{"label": "//features:Orders", "configurationId": 1}, {"label": "//storage:Database", "configurationId": 1}, {"label": "//storage:Database", "configurationId": 1}]"#
    )
    let graph = try await graph(json: json)
    let feature = try #require(graph.targets.first {
      $0.label == "//features:Orders" && $0.configuration?.checksum == "debug"
    })
    #expect(graph.transitiveTargetDependencies(of: feature).map(\.label) == [
      "//services:Store", "//storage:Database", "//storage:Database.swift",
    ])
  }

  @Test("Conflicting graph identities fail to load", arguments: [
    (
      original: #"{"id": 2, "checksum": "release"}"#,
      replacement: #"{"id": 1, "checksum": "release"}"#,
      reason: "configuration identifier"
    ),
    (
      original: #""configurationChecksum": "debug""#,
      replacement: #""configurationChecksum": "release""#,
      reason: "inconsistent configuration data"
    ),
    (
      original: #""configuredRuleInput": [{"label": "//storage:Database", "configurationId": 1}]"#,
      replacement: #""configuredRuleInput": [{"label": "//storage:Database"}]"#,
      reason: "omits dependency '//storage:Database'"
    ),
    (
      original: #""name": "//storage:Memory""#,
      replacement: #""name": "//services:Store""#,
      reason: "repeats configured target '//services:Store'"
    ),
  ])
  func conflictingIdentities(input: (
    original: String,
    replacement: String,
    reason: String
  )) async throws {
    let json = BazelGraphMock.json.replacing(
      input.original,
      with: input.replacement
    )
    await #expect {
      try await graph(json: json)
    } throws: { error in
      String(describing: error).contains(input.reason)
    }
  }

  private func graph(
    json: String = BazelGraphMock.json
  ) async throws -> BazelGraph {
    try await Codebase(root: .sources(["graph.json": json]))
      .bazelGraph(from: "graph.json")
  }
}
