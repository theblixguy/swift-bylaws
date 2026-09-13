import BylawsCore
import BylawsTestSupport
import Foundation
import Testing

@Suite("Automatic project roots")
struct AutomaticRootTests {
  @Test("Bazel markers identify the nearest workspace", arguments: [
    "MODULE.bazel", "WORKSPACE.bazel", "WORKSPACE",
  ])
  func bazelMarker(name: String) throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Nested/\(name)": "",
      "Nested/Rules/Bylaws.swift": "",
    ])
    let codebase = Codebase(root: .automatic(
      above: project.fileURL(for: "Nested/Rules/Bylaws.swift").path
    ))

    #expect(try codebase.resolvedRootPath() == project.fileURL(for: "Nested")
      .path)
  }

  @Test("A BUILD file does not replace the workspace root")
  func buildFile() throws {
    let project = try TemporaryProject(files: [
      "MODULE.bazel": "",
      "Sources/BUILD.bazel": "",
      "Sources/Bylaws.swift": "",
    ])
    let codebase = Codebase(root: .automatic(
      above: project.fileURL(for: "Sources/Bylaws.swift").path
    ))

    #expect(try codebase.resolvedRootPath() == project.rootURL.path)
  }
}
