import BylawsSemantics
import SwiftSyntax
import Testing

@Suite("Source language modes")
struct LanguageModeTests {
  @Test("Swift 5 permits attribute whitespace")
  func attributeWhitespace() throws {
    let file = try FileCollector.collect(
      source: "@available (swift, obsoleted: 1.0)\nstruct Legacy {}",
      path: "/project/Legacy.swift", swiftLanguageMode: .v5
    )

    #expect(file.structs.map(\.name) == ["Legacy"])
    #expect(file.swiftLanguageMode == .v5)
    #expect(file.withSyntax { !$0.hasError })
    let declaration = try #require(file.structs.first)
    let hasError = file.withSyntaxSession {
      $0.withSyntax(of: declaration, as: StructDeclSyntax.self) { $0.hasError }
    }
    #expect(hasError == false)
  }

  @Test("Swift 6 reports attribute whitespace at source position")
  func whitespaceDiagnostic() throws {
    let error = try #require(throws: ParseError.self) {
      try FileCollector.collect(
        source: "@available (swift, obsoleted: 1.0)\nstruct Legacy {}",
        path: "/project/Legacy.swift", swiftLanguageMode: .v6
      )
    }
    guard case let .didNotParse(diagnostics) = error else {
      Issue.record("Expected syntax diagnostics")
      return
    }
    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.location.filePath == "/project/Legacy.swift")
    #expect(diagnostic.location.line == 1)
    #expect(diagnostic.location.column == 11)
    #expect(diagnostic
      .message == "extraneous whitespace before '(' is not permitted")
    #expect(diagnostic.swiftLanguageMode == .v6)
  }

  @Test(
    "Incomplete declarations fail in every language mode",
    arguments: SwiftLanguageMode.allCases
  )
  func incompleteDeclaration(mode: SwiftLanguageMode) {
    #expect(throws: ParseError.self) {
      try FileCollector.collect(
        source: "struct Broken {",
        path: "/project/Broken.swift",
        swiftLanguageMode: mode
      )
    }
  }
}
