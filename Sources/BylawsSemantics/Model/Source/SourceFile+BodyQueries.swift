import SwiftSyntax

extension SourceFile {
  /// The assignments in the file, including those inside local functions and
  /// closures.
  ///
  /// The query includes every `#if` branch and parses the file on each access.
  public var assignments: [SourceAssignment] {
    let source = SourceText(
      source: sourceText,
      swiftLanguageMode: swiftLanguageMode
    )
    let collector = AssignmentCollector(source: source, path: path)
    collector.walk(swiftLanguageMode.parse(sourceText))
    return collector.assignments
  }

  /// The variable declarations and optional bindings at every scope.
  ///
  /// The query includes every `#if` branch and parses the file on each access.
  public var variableBindings: [VariableBinding] {
    let source = SourceText(
      source: sourceText,
      swiftLanguageMode: swiftLanguageMode
    )
    let collector = BindingCollector(source: source, path: path)
    collector.walk(swiftLanguageMode.parse(sourceText))
    return collector.bindings
  }
}

private final class AssignmentCollector: SyntaxVisitor {
  private let source: SourceText
  private let origin: DeclarationLocation
  private(set) var assignments: [SourceAssignment] = []

  init(source: SourceText, path: String) {
    self.source = source
    origin = .start(of: path)
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
    let expression = SourceExpression(
      ExprSyntax(node),
      source: source,
      origin: origin
    )
    if let assignment = SourceAssignment(expression) {
      assignments.append(assignment)
    }
    return .visitChildren
  }
}

private final class BindingCollector: SyntaxVisitor {
  private let source: SourceText
  private let origin: DeclarationLocation
  private(set) var bindings: [VariableBinding] = []

  init(source: SourceText, path: String) {
    self.source = source
    origin = .start(of: path)
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    bindings.append(contentsOf: node.bindings.map {
      VariableBinding(
        pattern: $0.pattern, initialValue: $0.initializer?.value,
        isMutable: node.bindingSpecifier.tokenKind == .keyword(.var),
        syntax: $0,
        source: source, origin: origin
      )
    })
    return .visitChildren
  }

  override func visit(_ node: OptionalBindingConditionSyntax)
    -> SyntaxVisitorContinueKind
  {
    bindings.append(VariableBinding(
      pattern: node.pattern, initialValue: node.initializer?.value,
      isMutable: node.bindingSpecifier.tokenKind == .keyword(.var),
      syntax: node,
      source: source, origin: origin
    ))
    return .visitChildren
  }
}
