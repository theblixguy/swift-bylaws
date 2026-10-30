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

  @Test(
    "Appending normalises dot components and keeps regular names",
    arguments: [
      ("/project", "Sources/../Tests", "/project/Tests"),
      ("", "/project/./Sources", "/project/Sources"),
      ("/project", "/../Other", "/Other"),
      ("../project", "../Other", "../Other"),
      ("/project", "File..swift", "/project/File..swift"),
      ("/", "../App.swift", "/App.swift"),
    ]
  )
  func appendedPaths(directory: String, child: String, expected: String) {
    #expect(LexicalFilePath(directory).appending(child).string == expected)
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

  @Test(
    "Containment and relative paths retain root semantics",
    arguments: [
      ("", "Sources/App.swift", true, Optional("Sources/App.swift")),
      ("", "/Sources/App.swift", true, nil),
      ("/", "/Sources/App.swift", true, "Sources/App.swift"),
      ("/", "Sources/App.swift", false, nil),
      ("/project", "/project", true, ""),
      ("/project", "/project-old/App.swift", false, nil),
      ("Sources", "Sources/App.swift", true, "App.swift"),
    ]
  )
  func rootSemantics(
    directory: String, candidate: String, contained: Bool, relative: String?
  ) {
    let directory = LexicalFilePath(directory)
    let candidate = LexicalFilePath(candidate)

    #expect(directory.contains(candidate) == contained)
    #expect(candidate.relative(to: directory)?.string == relative)
  }

  @Test("Unicode path spellings keep distinct component identities")
  func unicodeComponents() {
    let composed = LexicalFilePath("/project/\u{00E9}")
    let decomposed = LexicalFilePath("/project/e\u{0301}")

    #expect(composed != decomposed)
    #expect(Set([composed, decomposed]).count == 2)
    #expect(!composed.contains(decomposed.appending("App.swift")))
    #expect(!decomposed.contains(composed.appending("App.swift")))
  }

  @Test("Path operations retain components and hash identity")
  func derivedPaths() throws {
    let source = LexicalFilePath("/project/Sources/App.swift")
    let parent = source.removingLastComponent()
    let relative = try #require(source
      .relative(to: LexicalFilePath("/project")))

    #expect(parent.contains(source))
    #expect(parent.appending("Other.swift")
      == LexicalFilePath("/project/Sources/Other.swift"))
    #expect(LexicalFilePath("Sources").contains(relative))
    #expect(!parent.contains(relative))
    #expect(Set([parent, LexicalFilePath("/project/./Sources")]).count == 1)
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
