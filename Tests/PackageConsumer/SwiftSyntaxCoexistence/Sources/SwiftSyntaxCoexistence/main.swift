import Bylaws
import BylawsSyntax
import SwiftParser
import SwiftSyntax

enum CoexistenceError: Error {
  case unexpectedStatementCount
}

@main
enum SwiftSyntaxCoexistence {
  static func main() async throws {
    let codebase = Codebase(
      root: .sources(["Private.swift": "struct Private {}"])
    )
    guard let file = try await codebase.files.first else {
      throw CoexistenceError.unexpectedStatementCount
    }
    let privateStatementCount = file.withSyntax { $0.statements.count }
    let officialSyntax: SwiftSyntax.SourceFileSyntax = SwiftParser.Parser.parse(
      source: "struct Official {}"
    )
    guard privateStatementCount == 1,
          officialSyntax.statements.count == 1
    else {
      throw CoexistenceError.unexpectedStatementCount
    }
  }
}
