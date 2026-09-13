import BylawsInterpreter
import BylawsSemantics
import Testing
@testable import bylaws_cli

@Suite("GitHub path rendering")
struct GitHubPathRenderingTests {
  @Test("GitHub escapes a path outside the project")
  func gitHubEscapesAnOutsidePath() throws {
    let diagnostic = Diagnostic(
      severity: .error,
      location: DeclarationLocation.start(of: "/outside/A,B:C%\n.swift"),
      message: "failed"
    )

    let output = try render(
      reports: [],
      diagnostics: [diagnostic],
      format: .github,
      quiet: true,
      rootPath: "/project"
    )

    #expect(
      output == "::error file=/outside/A%2CB%3AC%25%0A.swift,line=1::failed"
    )
  }

  @Test("A GitHub annotation names the file relative to the project")
  func gitHubAnnotationPathIsRelative() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .warning,
          location: rulesFileLocation(),
          message: "a layer matched no file"
        ),
      ],
      format: .github,
      quiet: true,
      rootPath: "/project"
    )

    #expect(
      output == "::warning file=Bylaws.swift,line=4::a layer matched no file"
    )
  }

  @Test("A GitHub annotation uses an absolute path outside the project")
  func gitHubAnnotationKeepsOutsidePath() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .warning,
          location: rulesFileLocation(),
          message: "a layer matched no file"
        ),
      ],
      format: .github,
      quiet: true,
      rootPath: "/elsewhere"
    )

    #expect(
      output
        == "::warning file=/project/Bylaws.swift,line=4::a layer matched no file"
    )
  }

  @Test("A similar path prefix remains outside the project")
  func similarPrefixRemainsOutsideProject() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .warning,
          location: DeclarationLocation.start(
            of: "/project-old/Bylaws.swift"
          ),
          message: "failed"
        ),
      ],
      format: .github,
      quiet: true,
      rootPath: "/project"
    )

    #expect(
      output == "::warning file=/project-old/Bylaws.swift,line=1::failed"
    )
  }

  @Test("GitHub output escapes reserved characters in properties and messages")
  func gitHubAnnotationEscapesTheProperty() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .error,
          location: DeclarationLocation(
            filePath: "/project/Feature (v1,2)/Bylaws.swift",
            line: 4,
            column: 1,
            utf8Offset: 20
          ),
          message: "50% of the rules failed"
        ),
      ],
      format: .github,
      quiet: true,
      rootPath: "/project"
    )

    #expect(
      output == "::error file=Feature (v1%2C2)/Bylaws.swift,line=4::"
        + "50%25 of the rules failed"
    )
  }

  @Test("A trailing slash on the root leaves the path relative")
  func gitHubAnnotationAcceptsATrailingSlash() throws {
    let output = try render(
      reports: [],
      diagnostics: [
        Diagnostic(
          severity: .warning,
          location: rulesFileLocation(),
          message: "a layer matched no file"
        ),
      ],
      format: .github,
      quiet: true,
      rootPath: "/project/"
    )

    #expect(
      output == "::warning file=Bylaws.swift,line=4::a layer matched no file"
    )
  }
}
