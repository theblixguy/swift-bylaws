import BylawsCore
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing

@Suite("Lexical file paths")
struct LexicalFilePathTests {
  @Test("Normalisation removes dot components")
  func normalisationRemovesDotComponents() {
    #expect(
      LexicalFilePath("/project/./Sources/Generated/../App").string
        == "/project/Sources/App"
    )
  }

  @Test("Normalisation keeps the logical symbolic link path")
  func normalisationKeepsLogicalSymbolicLinkPath() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory
      .appendingPathComponent("bylaws-file-path-\(UUID().uuidString)")
    let real = root.appendingPathComponent("real")
    let link = root.appendingPathComponent("link")
    try manager.createDirectory(at: real, withIntermediateDirectories: true)
    try manager.createSymbolicLink(at: link, withDestinationURL: real)
    defer { try? manager.removeItem(at: root) }

    #expect(
      LexicalFilePath("\(link.path)/./App.swift").string
        == link.appendingPathComponent("App.swift").path
    )
  }

  @Test("Physical path resolves symbolic links")
  func physicalPathResolvesSymbolicLinks() throws {
    let manager = FileManager.default
    let project = try TemporaryProject(files: [:])
    let real = project.fileURL(for: "real")
    let link = project.fileURL(for: "link")
    try manager.createDirectory(at: real, withIntermediateDirectories: true)
    try manager.createSymbolicLink(at: link, withDestinationURL: real)

    let expected = try #require(
      LexicalFilePath(real.path).resolvingSymbolicLinks()
    )
    let actual = LexicalFilePath(link.path).resolvingSymbolicLinks()

    #expect(actual == expected)
  }

  @Test("Component membership matches a whole component")
  func componentMembershipMatchesWholeComponent() {
    let store = LexicalFilePath("/project/.build/index-build/debug/store")

    #expect(store.contains(component: "index-build"))
    #expect(!store.contains(component: "index"))
    #expect(!store.contains(component: "build"))
  }

  @Test("Containment compares complete components")
  func containmentComparesCompleteComponents() {
    let project = LexicalFilePath("/workspace/project")

    #expect(project.contains(LexicalFilePath("/workspace/project/App.swift")))
    #expect(!project
      .contains(LexicalFilePath("/workspace/project-old/App.swift")))
  }

  @Test("A descendant path becomes relative")
  func descendantPathBecomesRelative() {
    let project = LexicalFilePath("/workspace/project")

    #expect(
      LexicalFilePath("/workspace/project/Sources/App.swift")
        .relative(to: project)?.string == "Sources/App.swift"
    )
    #expect(project.relative(to: project)?.string == "")
    #expect(
      LexicalFilePath("/workspace/other/App.swift").relative(to: project) == nil
    )
  }

  @Test("A relative path resolves from its directory")
  func relativePathResolvesFromDirectory() {
    let sources = LexicalFilePath("/workspace/project/Sources")

    #expect(
      LexicalFilePath("../Tests/AppTests.swift", relativeTo: sources).string
        == "/workspace/project/Tests/AppTests.swift"
    )
    #expect(
      LexicalFilePath("/other/App.swift", relativeTo: sources).string
        == "/other/App.swift"
    )
  }

  @Test("A descendant cannot leave its directory")
  func descendantCannotLeaveDirectory() {
    let project = LexicalFilePath("/workspace/project")

    #expect(
      project.resolvingDescendant("Sources/../Tests")?.string
        == "/workspace/project/Tests"
    )
    #expect(project.resolvingDescendant("../other") == nil)
    #expect(project.resolvingDescendant("/other") == nil)
  }
}
