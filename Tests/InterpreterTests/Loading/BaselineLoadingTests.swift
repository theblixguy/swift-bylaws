import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Baseline loading")
struct BaselineLoadingTests {
  @Test("Parser returns every entry in a recorded baseline file")
  func readsRecordedEntries() throws {
    let entries = [
      Baseline.Entry(
        rule: "viewmodel-inheritance",
        declaration: "HomeViewModel",
        file: "Home.swift"
      ),
      Baseline.Entry(
        rule: "domain-ui-free",
        declaration: "",
        file: "User.swift"
      ),
      Baseline.Entry(
        rule: "quotes-\"-\\",
        declaration: "line one\nline two",
        file: "Sources/Feature \"A\"/Rule.swift"
      ),
    ]
    let project = try TemporaryProject(files: [
      "BylawsBaseline.swift": BaselineFile.render(
        name: "project",
        entries: entries
      ),
    ])

    let read = try Baseline.entries(
      fromFile: "\(project.rootURL.path)/BylawsBaseline.swift"
    )
    #expect(Set(read) == Set(entries))
  }

  @Test("A baseline with Swift parse errors is rejected")
  func parseErrorsDiagnose() throws {
    let project = try TemporaryProject(files: [
      "BylawsBaseline.swift": "extension Baseline {",
    ])

    let diagnostic = try #require(invalidBaselineDiagnostic(in: project))
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.location.filePath.hasSuffix("/BylawsBaseline.swift"))
  }

  @Test("A baseline rejects malformed Entry calls")
  func malformedEntriesDiagnose() throws {
    let project = try TemporaryProject(files: [
      "BylawsBaseline.swift": """
      import Bylaws

      extension Baseline {
        static let project = Baseline(
          "project",
          entries: [Entry(rule: "rule", declaration: "Declaration")]
        )
      }
      """,
    ])

    let diagnostic = try #require(invalidBaselineDiagnostic(in: project))
    #expect(diagnostic.message.contains("Entry"))
    #expect(diagnostic.location.line == 6)
  }

  @Test("Unrelated Swift is not an empty baseline")
  func unrelatedSwiftDiagnoses() throws {
    let project = try TemporaryProject(files: [
      "BylawsBaseline.swift": "let value = 1\n",
    ])

    let diagnostic = try #require(invalidBaselineDiagnostic(in: project))
    #expect(diagnostic
      .message == "the baseline file does not match the .record format")
    #expect(diagnostic.location.line == 1)
  }

  @Test(
    "Baseline filtering removes accepted offenders but leaves new offenders"
  )
  func filtersAcceptedOffenders() {
    let accepted = Offender(
      description: "HomeViewModel (Home.swift:1)",
      name: "HomeViewModel",
      location: DeclarationLocation(
        filePath: "/project/App/Home.swift",
        line: 1,
        column: 7,
        utf8Offset: 6
      )
    )
    let fresh = Offender(
      description: "ProfileViewModel (Profile.swift:1)",
      name: "ProfileViewModel",
      location: DeclarationLocation(
        filePath: "/project/App/Profile.swift",
        line: 1,
        column: 7,
        utf8Offset: 6
      )
    )
    let violations = Violations<Offender>(
      rule: "inherit from 'BaseViewModel'",
      offenders: [accepted, fresh],
      checkedCount: 3
    )

    let filtered = violations.removingOffenders(
      acceptedBy: [
        DiscoveredBaseline(
          path: "/project/Bylaws.baseline.swift",
          relativeDirectory: "",
          entries: [
            Baseline.Entry(
              rule: "viewmodel-inheritance",
              declaration: "HomeViewModel",
              file: "App/Home.swift"
            ),
          ]
        ),
      ],
      for: "viewmodel-inheritance",
      under: "/project"
    )
    #expect(filtered.offenders == [fresh])
    #expect(filtered.checkedCount == 3)
  }

  @Test(
    "A baseline entry with a shared basename matches only its recorded path"
  )
  func duplicateBasenamesStayDistinct() {
    let app = Offender(
      description: "App ViewModel",
      name: "ViewModel",
      location: DeclarationLocation.start(of: "/project/App/ViewModel.swift")
    )
    let feature = Offender(
      description: "Feature ViewModel",
      name: "ViewModel",
      location: DeclarationLocation.start(
        of: "/project/Feature/ViewModel.swift"
      )
    )
    let violations = Violations(
      rule: "inherit from BaseViewModel",
      offenders: [app, feature],
      checkedCount: 2
    )

    let filtered = violations.removingOffenders(
      acceptedBy: [
        DiscoveredBaseline(
          path: "/project/Bylaws.baseline.swift",
          relativeDirectory: "",
          entries: [
            Baseline.Entry(
              rule: "viewmodels",
              declaration: "ViewModel",
              file: "Feature/ViewModel.swift"
            ),
          ]
        ),
      ],
      for: "viewmodels",
      under: "/project"
    )

    #expect(filtered.offenders == [app])
  }

  @Test("An unreadable baseline reports its path")
  func missingFileDiagnoses() throws {
    let path = "/nonexistent/baseline.swift"
    let error = try #require(#expect(throws: BylawsFileError.self) {
      try Baseline.entries(fromFile: path)
    })
    let diagnostic = try #require(error.diagnostics.first)
    #expect(error.diagnostics.count == 1)
    #expect(diagnostic.message ==
      "cannot read the baseline file: " + readFailureDescription(at: path)
    )
    #expect(diagnostic.location.filePath == path)
    #expect(diagnostic.location.line == 1)
    #expect(diagnostic.location.column == 1)
  }

  private func invalidBaselineDiagnostic(
    in project: TemporaryProject
  ) -> Diagnostic? {
    do {
      _ = try Baseline.entries(
        fromFile: "\(project.rootURL.path)/BylawsBaseline.swift"
      )
      return nil
    } catch {
      return error.diagnostics.first
    }
  }
}
