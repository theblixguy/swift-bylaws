import BylawsSyntax

/// One attribute on a declaration, as written in source.
public struct Attribute: Sendable, Hashable, Codable, SourceProviding {
  private enum CodingKeys: String, CodingKey {
    case name, arguments
  }

  package var capturedSource: SourceSlice?

  /// The attribute name without the `@` sigil, such as `Test` or `MainActor`.
  public let name: String

  /// The raw text between the attribute's parentheses.
  ///
  /// `nil` indicates an attribute without arguments. For
  /// `@Test("Adds one item", .tags(.shoppingCart))`, the value is
  /// `"Adds one item", .tags(.shoppingCart)`.
  public let arguments: String?

  /// Creates an attribute from its source spelling.
  public init(name: String, arguments: String? = nil) {
    self.name = name
    self.arguments = arguments
  }

  /// The attribute's original source, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try capturedSource.required() }
  }

  /// The single unlabelled argument, or `nil` for another argument form.
  ///
  /// - Complexity: O(n), where n is the length of the source file.
  public var argument: SourceExpression? {
    guard let source = capturedSource else { return nil }
    let tree = source.snapshot.swiftLanguageMode.parse(source.snapshot.text)
    var node = tree.token(at: .init(utf8Offset: source.range.lowerBound))
      .map(Syntax.init)
    while let candidate = node {
      if let attribute = candidate.as(AttributeSyntax.self) {
        guard let arguments = attribute.arguments?
          .as(LabeledExprListSyntax.self),
          arguments.count == 1, let argument = arguments.first,
          argument.label == nil
        else { return nil }
        return SourceExpression(
          argument.expression,
          source: SourceText(
            source: source.snapshot.text,
            swiftLanguageMode: source.snapshot
              .swiftLanguageMode,
            filePath: source.filePath
          ),
          origin: .start(of: source.filePath)
        )
      }
      node = candidate.parent
    }
    return nil
  }

  /// Compares the attribute's spelling, excluding captured source.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name && lhs.arguments == rhs.arguments
  }

  /// Hashes the attribute's spelling, excluding captured source.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(arguments)
  }
}

extension Attribute: CustomStringConvertible {
  /// The attribute as written, such as `@MainActor`.
  public var description: String {
    if let arguments {
      return "@\(name)(\(arguments))"
    }
    return "@\(name)"
  }
}
