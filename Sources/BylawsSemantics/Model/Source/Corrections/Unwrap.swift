import BylawsSyntax

/// A correction that removes a supported wrapper and retains its direct content.
public struct Unwrap: SourceCorrectionProviding, Sendable {
  /// The proposed correction or the reason its applicability is undetermined.
  public let correction: SourceCorrection

  /// Checks a wrapper and retains its sole direct content when permitted.
  ///
  /// A missing target or a different content kind produces no correction.
  /// Else branches need an ordinary statement context. Contexts that could
  /// use a result builder produce an undetermined result.
  public init(
    _ target: (some SourceProviding)?,
    containingOnly kind: SourceNode.Kind? = nil
  ) throws {
    correction = try target?.source.unwrapped(containingOnly: kind)
      ?? .notApplicable
  }
}

extension SourceNode {
  /// Checks whether this wrapper can be replaced by its sole direct content.
  public func unwrapped(containingOnly kind: Kind? = nil) throws
    -> SourceCorrection
  {
    try source.unwrapped(containingOnly: kind)
  }
}

extension SourceSlice {
  /// Checks whether this captured wrapper can be removed without changing its context.
  ///
  /// Supports redundant expression and type parentheses and ordinary else-if
  /// branches.
  /// Other scope and call wrappers produce an undetermined result.
  public func unwrapped(containingOnly kind: SourceNode.Kind? = nil) throws
    -> SourceCorrection
  {
    let node = try syntaxNode()
    if let block = node.as(CodeBlockSyntax.self) {
      guard block.statements.count == 1,
            let item = block.statements.first else { return .notApplicable }
      let retained = Self.expression(in: Syntax(item.item))
      guard kind.map({ SourceNode.Kind(retained) == $0 }) ?? true else {
        return .notApplicable
      }
      guard let owner = block.parent?.as(IfExprSyntax.self),
            owner.elseBody?.id == block.id,
            retained.is(IfExprSyntax.self)
      else {
        return .undetermined(
          "Unwrap cannot establish whether removing this scope preserves behaviour. Use Replace with an explicit scope policy."
        )
      }
      guard Self.isStatement(owner),
            Self.isOrdinaryContext(Syntax(owner))
      else {
        return .undetermined(
          "Unwrap cannot establish an ordinary if statement context. Select code whose result-builder context is known."
        )
      }
      return try retaining(retained)
    }
    if let tuple = node.as(TupleExprSyntax.self) {
      guard tuple.elements.count == 1, let element = tuple.elements.first,
            element.label == nil, element.trailingComma == nil
      else {
        return .notApplicable
      }
      return try retaining(Syntax(element.expression), matching: kind)
    }
    if let tuple = node.as(TupleTypeSyntax.self) {
      guard tuple.elements.count == 1, let element = tuple.elements.first,
            element.firstName == nil, element.secondName == nil,
            element.ellipsis == nil, element.trailingComma == nil
      else {
        return .notApplicable
      }
      return try retaining(Syntax(element.type), matching: kind)
    }
    if let statement = node.as(ReturnStmtSyntax.self),
       let expression = statement.expression
    {
      guard kind.map({ SourceNode.Kind(Syntax(expression)) == $0 }) ?? true
      else {
        return .notApplicable
      }
      return .undetermined(
        "Unwrap cannot establish that an implicit return preserves type inference and result-builder behaviour. Use Replace for a rule with known return semantics."
      )
    }
    let scopedStatements = node.as(DoStmtSyntax.self)?.body.statements
      ?? node.as(ClosureExprSyntax.self)?.statements
      ?? node.as(FunctionCallExprSyntax.self)?.calledExpression
      .as(ClosureExprSyntax.self)?.statements
    if let scopedStatements {
      if let kind {
        guard scopedStatements.count == 1, let item = scopedStatements.first,
              SourceNode.Kind(Self.expression(in: Syntax(item.item))) == kind
        else { return .notApplicable }
      }
      return .undetermined(
        "Unwrap cannot establish the scope, capture and return effects. Use Replace with an explicit replacement."
      )
    }
    if let call = node.as(FunctionCallExprSyntax.self),
       call.arguments.count == 1, let argument = call.arguments.first
    {
      guard kind
        .map({ SourceNode.Kind(Syntax(argument.expression)) == $0 }) ?? true
      else {
        return .notApplicable
      }
      return .undetermined(
        "Unwrap cannot establish the call's effects and type conversions. Use Replace for a call with known semantics."
      )
    }
    return .notApplicable
  }

  private func retaining(
    _ syntax: Syntax,
    matching kind: SourceNode.Kind? = nil
  )
    throws -> SourceCorrection
  {
    guard kind.map({ SourceNode.Kind(syntax) == $0 }) ?? true else {
      return .notApplicable
    }
    let retained = try SourceSlice(
      snapshot: snapshot,
      range: syntax.positionAfterSkippingLeadingTrivia.utf8Offset
        ..< syntax.endPositionBeforeTrailingTrivia.utf8Offset
    )
    return try Replace(self, with: retained).correction
  }

  private static func expression(in node: Syntax) -> Syntax {
    node.as(ExpressionStmtSyntax.self).map { Syntax($0.expression) } ?? node
  }

  private static func isStatement(_ conditional: IfExprSyntax) -> Bool {
    var node = Syntax(conditional)
    while let parent = node.parent?.as(IfExprSyntax.self),
          parent.elseBody?.id == node.id { node = Syntax(parent) }
    return node.parent?.is(ExpressionStmtSyntax.self) == true
      || node.parent?.is(CodeBlockItemSyntax.self) == true
  }

  private static func isOrdinaryContext(_ syntax: Syntax) -> Bool {
    var node = syntax.parent
    while let current = node {
      if let closure = current.as(ClosureExprSyntax.self) {
        return containsReturn(Syntax(closure.statements))
      }
      if let function = current.as(FunctionDeclSyntax.self) {
        return function.body
          .map { containsReturn(Syntax($0.statements)) } == true
          || function.attributes.isEmpty
          && function.parent?.parent?.is(CodeBlockItemListSyntax.self) == true
      }
      if let accessor = current.as(AccessorDeclSyntax.self) {
        return accessor.body
          .map { containsReturn(Syntax($0.statements)) } == true
      }
      if current.is(AccessorBlockSyntax.self) {
        return containsReturn(current)
      }
      if current.is(VariableDeclSyntax.self) || current
        .is(SubscriptDeclSyntax.self)
        || current.is(InitializerDeclSyntax.self)
        || current.is(DeinitializerDeclSyntax.self) { return false }
      if current.is(SourceFileSyntax.self) { return true }
      node = current.parent
    }
    return false
  }

  private static func containsReturn(_ root: Syntax) -> Bool {
    var pending = [root]
    while let node = pending.popLast() {
      if node.is(ReturnStmtSyntax.self) { return true }
      if node.is(ClosureExprSyntax.self) || node
        .is(DeclSyntax.self) { continue }
      pending.append(contentsOf: node.children(viewMode: .sourceAccurate))
    }
    return false
  }
}
