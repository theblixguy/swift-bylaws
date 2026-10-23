#if os(macOS) || os(Linux)
  import Foundation
  import Testing

  @Suite("Portable CLI index corrections")
  struct CLICorrectionIndexProcessTests {
    @Test(
      "Portable correction verifies rebuilt compiler index",
      .timeLimit(.minutes(10))
    )
    func indexedCorrection() throws {
      let project = try CLIProcessProject(
        source: "public class LegacyMarker {}\n",
        rules: """
        import Bylaws
        import BylawsIndex

        let app = Codebase(including: ["Sources/App/**"], swiftLanguageMode: .v6)
        Rule("indexed-rename", "Legacy marker uses current name") {
          let definitions = try await app.definitions(of: "LegacyMarker")
          try await Violations(
            rule: "use CurrentMarker",
            offenders: definitions,
            checkedCount: 1
          ).withFix("Rename class") { _ in
            for declaration in try await app.classes.named("LegacyMarker") {
              try declaration.nameSource.replacement(with: "CurrentMarker")
            }
          }
        }
        """,
        extraFiles: [
          "Package.swift": """
          // swift-tools-version: 6.2
          import PackageDescription

          let package = Package(
            name: "IndexConsumer",
            targets: [.target(name: "App")]
          )
          """,
        ]
      )

      let correction = try project.run(
        "--autocorrect", "--skip-tests", "--format", "json"
      )

      try #require(
        correction.status == 0,
        "stdout:\n\(correction.standardOutput)\nstderr:\n\(correction.standardError)"
      )
      let report = try #require(JSONSerialization.jsonObject(
        with: Data(correction.standardOutput.utf8)
      ) as? [String: Any])
      let summary = try #require(report["summary"] as? [String: Int])
      #expect(summary["checkedRules"] == 1)
      #expect(summary["violations"] == 0)
      #expect(correction.standardError.contains("Corrected 1 file:"))
      #expect(correction.standardError.contains("Sources/App/App.swift"))
      #expect(try String(
        contentsOf: project.root
          .appendingPathComponent("Sources/App/App.swift"),
        encoding: .utf8
      ) == "public class CurrentMarker {}\n")
    }
  }
#endif
