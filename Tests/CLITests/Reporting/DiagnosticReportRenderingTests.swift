import BylawsInterpreter
import Foundation
import Testing
@testable import bylaws_cli

@Suite("Diagnostic report rendering")
struct DiagnosticReportRenderingTests {
  @Test("A configuration error creates a failed SARIF invocation")
  func configurationErrorAsSARIF() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .error,
          location: rulesFileLocation(),
          message: "cannot read the rules file"
        ),
      ],
      format: .sarif,
      quiet: true
    )

    #expect(output.contains("\"toolExecutionNotifications\""))
    #expect(output.contains("\"cannot read the rules file\""))
    #expect(output.contains("\"executionSuccessful\" : false"))
  }

  @Test("An execution error creates a GitHub error annotation")
  func executionErrorAsGitHubAnnotation() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .error,
          location: rulesFileLocation(),
          message: "rule 'layers' could not run"
        ),
      ],
      format: .github,
      quiet: true
    )

    #expect(
      output
        == "::error file=/project/Bylaws.swift,line=4::rule 'layers' could not run"
    )
  }

  @Test("A GitHub annotation includes the diagnostic hint")
  func gitHubAnnotationCarriesTheHint() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .error,
          location: rulesFileLocation(),
          message: "no Bylaws.swift found",
          hint: "declare rules at the project root"
        ),
      ],
      format: .github,
      quiet: true,
      rootPath: "/project"
    )

    #expect(
      output == "::error file=Bylaws.swift,line=4::no Bylaws.swift found "
        + "(declare rules at the project root)"
    )
  }

  @Test("GitHub output renders a notice with notice severity")
  func gitHubAnnotationRendersANotice() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .notice,
          location: rulesFileLocation(),
          message: "a rules file sits where discovery ignores it"
        ),
      ],
      format: .github,
      quiet: true,
      rootPath: "/project"
    )

    #expect(output.hasPrefix("::notice file=Bylaws.swift,line=4::"))
  }

  @Test("Xcode output replaces diagnostic line breaks with spaces")
  func xcodeDiagnosticIsOneLine() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .error,
          location: rulesFileLocation(),
          message: "first line\nsecond line\r\nthird line"
        ),
      ],
      format: .xcode,
      quiet: true
    )

    #expect(output.split(separator: "\n").count == 1)
    #expect(output.hasSuffix("first line second line third line"))
  }

  @Test("JSON reports have a stable schema and relative paths")
  func jsonReport() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .warning,
          location: rulesFileLocation(),
          message: "a rules file was ignored",
          hint: "move it to a discovered directory"
        ),
      ],
      format: .json,
      quiet: true,
      rootPath: "/project"
    )

    let value = try #require(
      JSONSerialization.jsonObject(with: Data(output.utf8))
        as? [String: Any]
    )
    let events = try #require(value["events"] as? [[String: Any]])

    #expect(value["schemaVersion"] as? Int == 1)
    #expect(events.first?["kind"] as? String == "diagnostic")
    #expect(events.first?["path"] as? String == "Bylaws.swift")
    #expect(events
      .first?["hint"] as? String == "move it to a discovered directory")
  }
}
