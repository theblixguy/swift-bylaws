import BylawsCore
import BylawsTestSupport
import Testing

@Suite("Configured Bazel dependencies")
struct BazelConfiguredEdgesTests {
  @Test("Split dependencies keep both target configurations")
  func split() async throws {
    let graph =
      try await Codebase(root: .sources(["graph.json": BazelGraphMock
          .splitJSON]))
      .bazelGraph(from: "graph.json")
    let app = try #require(graph.targets.first { $0.label == "//app:App" })
    let features = graph.directTargetDependencies(of: app)
      .filter { $0.label == "//features:Orders" }
    #expect(features.count == 2)
    #expect(features.compactMap(\.configuration?.checksum) == [
      "debug",
      "release",
    ])
    let reachable = graph.transitiveTargetDependencies(of: app)
      .filter { $0.label == "//features:Orders" }
    #expect(reachable == features)
  }

  @Test("Configured dependencies include inputs absent from rule attributes")
  func implicitDependency() async throws {
    let graph =
      try await Codebase(root: .sources(["graph.json": BazelGraphMock
          .splitJSON]))
      .bazelGraph(from: "graph.json")
    let app = try #require(graph.targets.first { $0.label == "//app:App" })
    #expect(graph.directTargetDependencies(of: app).map(\.label) == [
      "//features:Orders", "//features:Orders", "//storage:Database",
    ])
  }
}
