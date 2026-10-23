import Bylaws
import BylawsSyntax
import Testing

enum FormattingRule {
  enum Layout: Sendable {
    case statements, properties, calls, all
  }

  static func violations(
    in codebase: Codebase,
    layout: Layout = .all,
    maximumLineLength: Int? = nil
  ) async throws -> Violations<SourceFile> {
    try await codebase.files
      .violations(matching: Matcher<SourceFile>("need source formatting") {
        formatted($0, layout: layout, maximumLineLength: maximumLineLength)
          != $0.sourceText
      })
      .withFix("Format source") { context in
        try context.source.replacement(with: formatted(
          context.offender,
          layout: layout,
          maximumLineLength: maximumLineLength
        ))
      }
  }

  private static func formatted(
    _ file: SourceFile,
    layout: Layout,
    maximumLineLength: Int?
  ) -> String {
    file.withSyntax { tree in
      var result = Syntax(tree)
      if layout == .properties || layout == .all {
        result = PropertyGroupingRewriter().rewrite(result)
      }
      if layout == .statements || layout == .all {
        result = StatementSpacingRewriter().rewrite(result)
      }
      if layout == .calls || layout == .all {
        result = MultilineCallRewriter(
          maximumLineLength: maximumLineLength
        ).rewrite(result)
      }
      return result.description
    }
  }
}
