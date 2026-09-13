import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable file paths")
struct PathEvaluationTests {
  @Test("File URL returns parent path")
  func parentPath() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      import Bylaws
      import Foundation
      let app = Codebase(including: ["Sources/**"])
      let rules = [Rule("paths", "Parent folder matched") {
        let matches = Matcher<Class>("have the expected parent") { _ in
          URL(fileURLWithPath: "/Features/Orders/Views/OrderView.swift")
            .deletingLastPathComponent().deletingLastPathComponent().path
            == "/Features/Orders"
        }
        return try await app.classes.violations(of: matches)
      }]
      """,
      "Sources/App.swift": "class Example {}",
    ])

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }

  @Test("File URL matches Foundation path behaviour", arguments: [
    "/", "/Features/Orders/", "/Features/../Orders/View.swift",
    "/Feature name/Order%20View.swift", "Sources/Orders/View.swift", "",
  ])
  func foundationPaths(_ path: String) async throws {
    let url = URL(fileURLWithPath: path)
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      import Bylaws
      import Foundation
      let app = Codebase(including: ["Sources/**"])
      let rules = [Rule("paths", "File paths match Foundation") {
        let url: URL = URL(fileURLWithPath: "\(path)")
        let matches = Matcher<Class>("match the file URL") { _ in
          url.path == "\(url.path)"
            && url.lastPathComponent == "\(url.lastPathComponent)"
            && url.pathExtension == "\(url.pathExtension)"
            && url.deletingLastPathComponent().path == "\(url
        .deletingLastPathComponent().path)"
        }
        return try await app.classes.violations(of: matches)
      }]
      """,
      "Sources/App.swift": "class Example {}",
    ])

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 1)
  }
}
