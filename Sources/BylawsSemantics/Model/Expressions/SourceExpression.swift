import SwiftParser
import SwiftSyntax

/// An expression from a Swift source file.
public struct SourceExpression: Declaration {
  let syntax: ExprSyntax
  let context: SourceContext

  var source: SourceText { context.source }
  var origin: DeclarationLocation { context.origin }

  init(
    _ syntax: ExprSyntax, source: SourceText, origin: DeclarationLocation,
    inheritedDeclarations: [EnclosingDeclaration] = [],
    inheritedBranches: [CompilationBranch] = []
  ) {
    self.syntax = syntax
    context = SourceContext(
      source: source, origin: origin,
      inheritedDeclarations: inheritedDeclarations,
      inheritedBranches: inheritedBranches
    )
  }

  static func parse(
    _ text: String, at location: DeclarationLocation,
    swiftLanguageMode: SwiftLanguageMode
  ) -> Self? {
    let tree = swiftLanguageMode.parse(text)
    guard !tree.hasError, tree.statements.count == 1,
          let expression = tree.statements.first?.item.as(ExprSyntax.self)
    else { return nil }
    return Self(
      expression,
      source: SourceText(source: text, swiftLanguageMode: swiftLanguageMode),
      origin: location
    )
  }

  /// The expression text, excluding leading and trailing trivia.
  ///
  /// - Complexity: O(n), where n is the expression's length.
  public var text: String { source.trimmedText(of: syntax) }

  /// The expression text.
  public var name: String { text }

  /// The expression's start in the source file.
  public var location: DeclarationLocation {
    location(at: syntax.positionAfterSkippingLeadingTrivia)
  }

  func location(at start: AbsolutePosition) -> DeclarationLocation {
    context.location(at: start)
  }

  /// The decoded value of a string literal, or `nil` for an interpolated
  /// string or another kind of expression.
  public var stringValue: String? {
    syntax.as(StringLiteralExprSyntax.self)?.representedLiteralValue
  }

  /// The integer literal's value when it fits in `Int`.
  public var integerValue: Int? {
    syntax.as(IntegerLiteralExprSyntax.self)?.representedLiteralValue
  }

  /// The value parsed from a floating-point literal.
  ///
  /// Returns `nil` for other expressions or if the literal cannot be parsed
  /// as a `Double`.
  public var floatingPointValue: Double? {
    syntax.as(FloatLiteralExprSyntax.self)?.representedLiteralValue
  }

  /// The Boolean literal's value, or `nil` for other expressions.
  public var booleanValue: Bool? {
    syntax.as(BooleanLiteralExprSyntax.self)
      .map { $0.literal.tokenKind == .keyword(.true) }
  }

  /// Whether the expression is the `nil` literal.
  public var isNilLiteral: Bool { syntax.is(NilLiteralExprSyntax.self) }

  /// The identifier or member name, without a receiver or argument labels.
  public var referenceName: String? {
    referenceToken?.text
  }

  /// The identifier token's location, or `nil` for other expressions.
  ///
  /// For `store.save`, this is the location of `save`.
  public var referenceLocation: DeclarationLocation? {
    referenceToken.map { location(at: $0.positionAfterSkippingLeadingTrivia) }
  }

  private var referenceToken: TokenSyntax? {
    if let reference = syntax.as(DeclReferenceExprSyntax.self) {
      reference.baseName
    } else {
      syntax.as(MemberAccessExprSyntax.self)?.declName.baseName
    }
  }

  /// The receiver of a member reference, such as `store` in `store.save`.
  public var base: Self? {
    syntax.as(MemberAccessExprSyntax.self)?.base.map(child)
  }

  /// The called expression, such as `store.save` in `store.save(value)`.
  public var calledExpression: Self? {
    syntax.as(FunctionCallExprSyntax.self).map { child($0.calledExpression) }
  }

  /// Compares expressions by their text and source location.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.location == rhs.location && lhs.text == rhs.text
  }

  /// Hashes the expression's text and source location.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(location)
    hasher.combine(text)
  }

  func child(_ node: ExprSyntax) -> Self {
    Self(
      node, source: source, origin: origin,
      inheritedDeclarations: context.inheritedDeclarations,
      inheritedBranches: context.inheritedBranches
    )
  }
}

extension SourceExpression: CustomStringConvertible {
  /// The expression text.
  public var summary: String { text }
}
