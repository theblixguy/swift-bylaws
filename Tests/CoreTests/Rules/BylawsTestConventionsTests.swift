import Bylaws
import SwiftSyntax
import Testing

@Suite("Test conventions", .codebase(.bylaws), .tags(.layering))
struct BylawsTestConventionsTests {
  @Test("Test suites are structs")
  func suitesAreStructs() async throws {
    let classSuites = try await Codebase.bylawsTests.classes
      .suffixed("Tests")
    #expect(classSuites.isEmpty)
  }

  @Test(
    "Tests have display names",
    arguments: try await Codebase.bylawsTests.files
  )
  func displayNames(_ file: SourceFile) {
    file.withSyntaxSession { syntax in
      for function in file.functions
        where function.hasAttribute("Test") || function
        .hasAttribute("Testing.Test")
      {
        let hasName = syntax.withSyntax(
          of: function, as: FunctionDeclSyntax.self,
          Self.hasDisplayName
        )
        #expect(hasName == true, sourceLocation: function.testingLocation)
      }
    }
  }

  @Test(
    "Display names use first unlabelled string argument",
    arguments: [
      ("@Test", false),
      ("@Test()", false),
      ("@Test(arguments: [\"example\"])", false),
      ("@Test(.bug(\"https://example.com/1\"))", false),
      ("@Test(\"Returns the result\")", true),
      ("@Test(\"Returns the result\", arguments: [\"example\"])", true),
      ("@Testing.Test(\"Returns the result\")", true),
      ("@Testing.Test(arguments: [\"example\"])", false),
      ("@Test(/* Display name */ \"Returns the result\")", true),
      ("@Test(#\"Returns the result\"#)", true),
    ]
  )
  func displayNameArguments(attribute: String, expected: Bool) async throws {
    let codebase = Codebase(root: .sources([
      "Test.swift": "\(attribute) func check() {}",
    ]))
    let file = try #require(try await codebase.files.first)
    try file.withSyntax { syntax in
      let function = try #require(
        syntax.statements.first?.item.as(FunctionDeclSyntax.self)
      )
      #expect(Self.hasDisplayName(function) == expected)
    }
  }

  private static func hasDisplayName(_ function: FunctionDeclSyntax) -> Bool {
    let attribute = function.attributes.compactMap {
      $0.as(AttributeSyntax.self)
    }.first {
      ["Test", "Testing.Test"].contains($0.attributeName.trimmedDescription)
    }
    guard let first = attribute?.arguments?
      .as(LabeledExprListSyntax.self)?.first
    else { return false }
    return first.label == nil && first.expression
      .is(StringLiteralExprSyntax.self)
  }
}
