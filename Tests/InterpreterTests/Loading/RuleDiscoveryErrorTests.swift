import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Testing

@Suite("Rule discovery errors")
struct RuleDiscoveryErrorTests {
  @Test("An unresolved root reports the codebase error's message")
  func describesAnUnresolvedRoot() {
    let cause = CodebaseError.rootNotFound(searchedFrom: "/project/Tests")
    let error = RuleDiscoveryError.unresolvedRoot(cause)
    #expect(error.description == cause.description)
  }

  @Test("Invalid rules report every diagnostic")
  func describesInvalidRules() {
    let diagnostic = Diagnostic(
      severity: .error,
      location: DeclarationLocation(
        filePath: "/project/Bylaws.swift",
        line: 3,
        column: 5,
        utf8Offset: 40
      ),
      message: "unknown rule 'noSingletons'"
    )
    let cause = BylawsFileError(diagnostics: [diagnostic])
    let error = RuleDiscoveryError.invalidRules(cause)
    #expect(error.description == cause.description)
    #expect(error.description.contains("/project/Bylaws.swift:3:5"))
  }

  @Test("Errors with different causes are not equal")
  func distinguishesCauses() {
    let first = RuleDiscoveryError.unresolvedRoot(
      .rootNotFound(searchedFrom: "/a")
    )
    let second = RuleDiscoveryError.unresolvedRoot(
      .rootNotFound(searchedFrom: "/b")
    )
    #expect(first != second)
    #expect(first == .unresolvedRoot(.rootNotFound(searchedFrom: "/a")))
  }
}
