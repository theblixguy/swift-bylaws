import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Folder findings")
struct FolderFindingTests {
  @Test("A folder finding keeps its reporting location and affected path")
  func reportingLocation() async throws {
    let app =
      Codebase(root: .sources(["Sources/App/Models/A.swift": "struct A {}"]))
    let location = DeclarationLocation.start(of: "/project/Bylaws.swift")
    let result = try await app.checkFolderLayout(
      matching: "Sources/App",
      containing: ["Views"]
    )
    .findings(reportedAt: location)
    let offender = try #require(result.violations.offenders.first)
    #expect(offender.name == "Sources/App/Views")
    #expect(offender.location == location)
    #expect(offender.affectedPath == "/virtual/Sources/App/Views")
    #expect(result.violations.erased().offenders.first == offender)
  }

  @Test("A baseline uses the affected folder path")
  func baselinePath() {
    let offender = Offender(
      description: "missing folder 'Sources/App/Views'",
      name: "Sources/App/Views",
      location: .start(of: "/project/Bylaws.swift"),
      affectedPath: "/project/Sources/App/Views"
    )
    let entry = Baseline.Entry(
      offender: offender,
      for: "folders",
      relativeTo: "/project"
    )
    #expect(entry == Baseline.Entry(
      rule: "folders",
      declaration: "Sources/App/Views",
      file: "Sources/App/Views"
    ))
  }

  @Test("Encoding preserves the affected folder path")
  func encodedPath() throws {
    let offender = Offender(
      description: "missing folder 'Views'",
      name: "Views",
      location: .start(of: "/project/Bylaws.swift"),
      affectedPath: "/project/Views"
    )
    let encoded = try JSONEncoder().encode(offender)
    let decoded = try JSONDecoder().decode(Offender.self, from: encoded)
    #expect(decoded == offender)
  }
}
