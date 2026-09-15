import BylawsCore
import BylawsTestSupport
import Foundation
import Testing

@Suite("Bazel build settings")
struct BazelConfigurationTests {
  @Test("Configuration retains option groups and tool status")
  func options() async throws {
    let codebase =
      Codebase(root: .sources(["graph.json": BazelGraphMock.settingsJSON]))
    let graph = try await codebase.bazelGraph(from: "graph.json")
    let target = try #require(graph.targets.first)
    let configuration = try #require(target.configuration)
    let options = configuration.buildOptions
    #expect(configuration.checksum == "exec")
    #expect(configuration.isTool)
    #expect(options["CoreOptions"]?["compilation_mode"] == "opt")
    #expect(options["PlatformOptions"]?["platforms"] == "[//platforms:phone]")
    #expect(options["user-defined"]?["//settings:api"] == "v2")
    #expect(options["OtherOptions"]?["compilation_mode"] == "custom")
    #expect(options["EmptyOptions"] == [:])
  }

  @Test("Omitted configuration fields use protobuf defaults")
  func defaults() async throws {
    let codebase = Codebase(root: .sources(["graph.json": BazelGraphMock.json]))
    let graph = try await codebase.bazelGraph(from: "graph.json")
    let configuration = try #require(graph.targets.first?.configuration)
    #expect(!configuration.isTool)
    #expect(configuration.buildOptions.isEmpty)
  }

  @Test("Repeated option groups or names fail", arguments: [
    (
      original: "OtherOptions",
      replacement: "CoreOptions",
      reason: "repeats option group"
    ),
    (
      original: "unrelated_option",
      replacement: "compilation_mode",
      reason: "repeats option"
    ),
  ])
  func repeatedOptions(input: (
    original: String,
    replacement: String,
    reason: String
  )) async throws {
    let json = BazelGraphMock.settingsJSON.replacing(
      input.original,
      with: input.replacement
    )
    let codebase = Codebase(root: .sources(["graph.json": json]))
    await #expect {
      try await codebase.bazelGraph(from: "graph.json")
    } throws: { error in
      String(describing: error).contains(input.reason)
    }
  }
}
