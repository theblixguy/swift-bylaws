import ArgumentParser
import Testing
@testable import bylaws_cli

@Suite("Rules command paths")
struct RulesCommandTests {
  @Test("A path below the root becomes relative")
  func pathBelowRoot() throws {
    #expect(
      try RulesCommand.relative(
        "/project/Sources/App.swift",
        toRoot: "/project"
      ) == "Sources/App.swift"
    )
  }

  @Test("The root becomes an empty relative path")
  func rootPath() throws {
    #expect(try RulesCommand.relative("/project", toRoot: "/project") == "")
  }

  @Test("A path below the filesystem root becomes relative")
  func pathBelowFilesystemRoot() throws {
    #expect(
      try RulesCommand.relative("/project/App.swift", toRoot: "/")
        == "project/App.swift"
    )
  }

  @Test("A path outside the root is rejected")
  func pathOutsideRoot() {
    #expect(throws: PathOutsideRootError.self) {
      try RulesCommand.relative("/other/App.swift", toRoot: "/project")
    }
  }

  @Test("A path cannot leave the root with parent components")
  func parentComponentsCannotLeaveRoot() {
    #expect(throws: PathOutsideRootError.self) {
      try RulesCommand.relative(
        "/project/Sources/../../other/App.swift",
        toRoot: "/project"
      )
    }
  }
}
