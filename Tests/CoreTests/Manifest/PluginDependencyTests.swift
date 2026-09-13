import Bylaws
import BylawsTestSupport
import Foundation
import Testing

@Suite("Package dependency checking with a plugin", .tags(.layering))
struct PluginDependencyTests {
  init() throws {
    project = try TemporaryProject(
      files: [
        "Package.swift": """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
          name: "App",
          targets: [
            .executableTarget(name: "tool"),
            .plugin(
              name: "ToolPlugin",
              capability: .command(
                intent: .custom(verb: "tool", description: "Runs the tool.")
              ),
              dependencies: [.target(name: "tool")]
            ),
          ]
        )
        """,
        "Sources/tool/main.swift": "print(\"hello\")",
        "Plugins/ToolPlugin/ToolPlugin.swift": "import PackagePlugin",
      ]
    )
  }

  @Test("Plugin sources come from the Plugins directory")
  func pluginSourcesAreFound() async throws {
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**", "Plugins/**"]
    )
    let result = try await codebase.checkPackageDependencies()
    #expect(result.emptyTargets.isEmpty)
  }

  @Test("Package dependency checking marks a plugin executable as used")
  func executableDependencyIsNotUnused() async throws {
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**", "Plugins/**"]
    )
    let result = try await codebase.checkPackageDependencies()
    #expect(result.unused.isEmpty)
  }

  private let project: TemporaryProject
}
