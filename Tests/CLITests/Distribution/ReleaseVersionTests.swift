import BylawsCore
import BylawsRunner
import Foundation
import Testing

@Suite("Release version source")
struct ReleaseVersionTests {
  @Test("Release workflow selects the current version file")
  func versionFile() throws {
    let root = URL(fileURLWithPath: try Codebase
      .automaticRoot(above: #filePath))
    let workflow = try String(
      contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
      encoding: .utf8
    )
    let assignment = try #require(workflow
      .firstMatch(of: /VERSION_FILE="([^"]+)"/))
    let source = try String(
      contentsOf: root.appendingPathComponent(String(assignment.1)),
      encoding: .utf8
    )
    #expect(source
      .contains("package static let current = \"\(BylawsVersion.current)\""))
  }
}
