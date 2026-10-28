import BylawsSyntax

/// An assignment using `=` or a standard compound-assignment operator.
public struct SourceAssignment: Declaration {
  private let originalSource: ParsedSource?
  /// The expression on the left of the assignment operator.
  public let target: SourceExpression

  /// The expression on the right of the assignment operator.
  public let value: SourceExpression

  /// The assignment operator, such as `=` or `+=`.
  public let operatorName: String

  /// The named declarations that contain the assignment, starting with the
  /// nearest declaration.
  public let enclosingDeclarations: [EnclosingDeclaration]

  /// The conditional-compilation branches that contain the assignment,
  /// starting with the outermost branch.
  public let compilationBranches: [CompilationBranch]

  /// The target expression's text.
  public var name: String { target.text }

  /// The start of the target expression.
  public var location: DeclarationLocation { target.location }

  init?(_ expression: SourceExpression) {
    guard let sequence = expression.syntax.as(SequenceExprSyntax.self)
    else { return nil }
    let elements = Array(sequence.elements)
    guard elements.count >= 3 else { return nil }
    let operation = elements[1]
    let operatorName: String
    if operation.is(AssignmentExprSyntax.self) {
      operatorName = "="
    } else if let binary = operation.as(BinaryOperatorExprSyntax.self),
              Self.compoundOperators.contains(binary.operator.text)
    {
      operatorName = binary.operator.text
    } else {
      return nil
    }
    target = expression.child(elements[0])
    originalSource = expression.context.parsedSource(of: expression.syntax)
    self.operatorName = operatorName
    enclosingDeclarations = expression.enclosingDeclarations
    compilationBranches = expression.compilationBranches
    if elements.count == 3 {
      value = expression.child(elements[2])
    } else {
      let right =
        SequenceExprSyntax(elements: ExprListSyntax(elements.dropFirst(2)))
      value = SourceExpression(
        ExprSyntax(right),
        source: SourceText(
          source: right.description,
          swiftLanguageMode: expression.sourceTextContext.swiftLanguageMode,
          capturedBuffer: expression.sourceTextContext.capturedBuffer
        ),
        origin: expression.location(at: elements[2].position),
        inheritedDeclarations: enclosingDeclarations,
        inheritedBranches: compilationBranches
      )
    }
  }

  /// The assignment's source, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try originalSource.required().whole }
  }

  private static let compoundOperators: Set<String> = [
    "+=", "-=", "*=", "/=", "%=", "&+=", "&-=", "&*=",
    "&=", "|=", "^=", "<<=", ">>=", "&<<=", "&>>=",
  ]
}
