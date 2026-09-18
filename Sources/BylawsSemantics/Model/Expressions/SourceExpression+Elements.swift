import BylawsSyntax

extension SourceExpression {
  /// An argument in a call or string interpolation.
  public struct Argument: Sendable, Hashable {
    /// The argument label, or `nil` for an unlabelled argument.
    public let label: String?

    /// The argument expression.
    public let expression: SourceExpression
  }

  /// A key-value pair in a dictionary literal.
  public struct DictionaryElement: Sendable, Hashable {
    /// The key expression.
    public let key: SourceExpression

    /// The value expression.
    public let value: SourceExpression
  }

  /// The array literal's elements, or `nil` for other expressions.
  ///
  /// - Complexity: O(n), where n is the number of elements.
  public var arrayElements: [Self]? {
    syntax.as(ArrayExprSyntax.self)?.elements.map { child($0.expression) }
  }

  /// The dictionary literal's entries in source order, including repeated keys.
  ///
  /// Returns `nil` for other expressions.
  ///
  /// - Complexity: O(n), where n is the number of entries.
  public var dictionaryElements: [DictionaryElement]? {
    guard let dictionary = syntax.as(DictionaryExprSyntax.self)
    else { return nil }
    return dictionary.content.as(DictionaryElementListSyntax.self)?.map {
      DictionaryElement(key: child($0.key), value: child($0.value))
    } ?? []
  }

  /// The call's parenthesised arguments, or `nil` for other expressions.
  ///
  /// - Complexity: O(n), where n is the number of arguments.
  public var arguments: [Argument]? {
    syntax.as(FunctionCallExprSyntax.self)?.arguments.map(argument)
  }

  /// The argument lists of the string's interpolations, in source order.
  ///
  /// Returns an empty array for a string without interpolation or a non-string
  /// expression.
  ///
  /// - Complexity: O(n), where n is the number of string segments and arguments.
  public var interpolations: [[Argument]] {
    syntax.as(StringLiteralExprSyntax.self)?.segments.compactMap {
      $0.as(ExpressionSegmentSyntax.self)?.expressions.map(argument)
    } ?? []
  }

  private func argument(_ node: LabeledExprSyntax) -> Argument {
    Argument(label: node.label?.text, expression: child(node.expression))
  }
}
