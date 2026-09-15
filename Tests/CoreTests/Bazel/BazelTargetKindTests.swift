import BylawsCore
import BylawsSemantics
import Testing

@Suite("Bazel target kinds")
struct BazelTargetKindTests {
  @Test("Unknown target kinds report their value", arguments: [
    "ENVIRONMENT_GROUP", "NEW_KIND", "rule", "",
  ])
  func unknownKind(kind: String) async {
    let json = #"{"results":[{"target":{"type":"\#(kind)"}}]}"#
    let codebase = Codebase(root: .sources(["graph.json": json]))
    await #expect(throws: CodebaseError.bazelGraph(
      path: "/virtual/graph.json",
      reason: "The export contains unsupported target type '\(kind)'."
    )) {
      try await codebase.bazelGraph(from: "graph.json")
    }
  }

  @Test("Missing or non-string target kinds fail to decode", arguments: [
    "{}", #"{"type":null}"#, #"{"type":42}"#,
    #"{"type":{}}"#, #"{"type":[]}"#,
  ])
  func malformedKind(target: String) async {
    let json = #"{"results":[{"target":\#(target)}]}"#
    let codebase = Codebase(root: .sources(["graph.json": json]))
    await #expect(throws: CodebaseError.bazelGraph(
      path: "/virtual/graph.json",
      reason: "The file must contain a configured cquery JSON result."
    )) {
      try await codebase.bazelGraph(from: "graph.json")
    }
  }

  @Test("Generated files retain their generating rule")
  func generatedFile() async throws {
    let graph = try await graph()
    let generated = try #require(graph.targets
      .first { $0.label == "//:Generated.swift" })
    #expect(generated.configuration?.checksum == "debug")
    #expect(generated.ruleClass == nil)
    #expect(graph.directTargetDependencies(of: generated)
      .map(\.label) == ["//:generator"])
    #expect(graph.transitiveTargetDependencies(of: generated).map(\.label) == [
      "//:generator", "@@tools//:generator",
    ])
  }

  @Test("Aliases retain dependencies across repositories")
  func alias() async throws {
    let graph = try await graph()
    let alias = try #require(graph.targets.first { $0.label == "//:alias" })
    let dependencies = graph.directTargetDependencies(of: alias)
    #expect(dependencies.map(\.label) == ["@@tools//:generator"])
    #expect(dependencies.map(\.configuration?.checksum) == ["exec"])
    #expect(alias.location
      .filePath == "/virtual/folder:with:colons/BUILD.bazel")
    #expect(alias.location.line == 12)
    #expect(alias.location.column == 5)
  }

  @Test("Package groups retain included groups")
  func packageGroup() async throws {
    let graph = try await graph()
    let group = try #require(graph.targets.first { $0.label == "//:allowed" })
    #expect(group.configuration == nil)
    #expect(graph.directTargetDependencies(of: group)
      .map(\.label) == ["//:shared"])
  }

  private func graph() async throws -> BazelGraph {
    let json = #"""
    {
      "configurations": [{"id": 1, "checksum": "debug"}, {"id": 2, "checksum": "exec"}],
      "results": [
        {"configurationId": 1, "target": {"type": "GENERATED_FILE", "generatedFile": {
          "name": "//:Generated.swift", "generatingRule": "//:generator"
        }}},
        {"configurationId": 1, "target": {"type": "RULE", "rule": {
          "name": "//:generator", "ruleClass": "genrule",
          "configuredRuleInput": [{"label": "@@tools//:generator", "configurationId": 2}]
        }}},
        {"configurationId": 2, "target": {"type": "RULE", "rule": {
          "name": "@@tools//:generator", "ruleClass": "swift_binary"
        }}},
        {"configurationId": 1, "target": {"type": "RULE", "rule": {
          "name": "//:alias", "ruleClass": "alias", "location": "folder:with:colons/BUILD.bazel:12:5",
          "configuredRuleInput": [{"label": "@@tools//:generator", "configurationId": 2}]
        }}},
        {"target": {"type": "PACKAGE_GROUP", "packageGroup": {
          "name": "//:allowed", "includedPackageGroup": ["//:shared"]
        }}},
        {"target": {"type": "PACKAGE_GROUP", "packageGroup": {"name": "//:shared"}}}
      ]
    }
    """#
    return try await Codebase(root: .sources(["graph.json": json]))
      .bazelGraph(from: "graph.json")
  }
}
