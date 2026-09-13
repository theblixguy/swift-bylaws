import SwiftSyntax

struct RuntimeStatementParser {
  let syntax: RulesSyntaxContext

  func parse(
    _ items: CodeBlockItemListSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeBody? {
    var statements: [RuntimeStatement] = []
    for item in items {
      guard let statement = parse(item, diagnostics: &diagnostics) else {
        return nil
      }
      statements.append(statement)
    }
    return RuntimeBody(statements: statements)
  }

  private func parse(
    _ item: CodeBlockItemSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeStatement? {
    let location = syntax.location(of: item)
    switch item.item {
    case let .expr(expression):
      if let conditional = expression.as(IfExprSyntax.self) {
        return parse(conditional, diagnostics: &diagnostics)
      }
      guard let value = RuntimeExpressionParser(syntax: syntax).parse(
        expression,
        diagnostics: &diagnostics
      )
      else { return nil }
      return RuntimeStatement(kind: .expression(value), location: location)
    case let .stmt(statement):
      if let loop = statement.as(ForStmtSyntax.self) {
        guard loop.tryKeyword == nil, loop.awaitKeyword == nil,
              loop.caseKeyword == nil, loop.whereClause == nil,
              let name = loop.pattern.as(IdentifierPatternSyntax.self)?
              .identifier.text,
              let sequence = RuntimeExpressionParser(syntax: syntax).parse(
                loop.sequence,
                diagnostics: &diagnostics
              ),
              let body = parse(loop.body.statements, diagnostics: &diagnostics)
        else {
          diagnostics.append(unsupported(item))
          return nil
        }
        return RuntimeStatement(
          kind: .forStatement(name: name, sequence: sequence, body: body),
          location: location
        )
      }
      if let expression = statement.as(ExpressionStmtSyntax.self)?.expression,
         let conditional = expression.as(IfExprSyntax.self)
      {
        return parse(conditional, diagnostics: &diagnostics)
      }
      if let guarded = statement.as(GuardStmtSyntax.self) {
        guard guarded.conditions.count == 1,
              let element = guarded.conditions.first,
              let condition = parse(
                element.condition,
                diagnostics: &diagnostics
              ),
              let failure = parse(
                guarded.body.statements,
                diagnostics: &diagnostics
              )
        else {
          diagnostics.append(unsupported(item))
          return nil
        }
        return RuntimeStatement(
          kind: .guardStatement(condition: condition, failure: failure),
          location: location
        )
      }
      guard let returned = statement.as(ReturnStmtSyntax.self) else {
        diagnostics.append(unsupported(item))
        return nil
      }
      let value: RuntimeExpression?
      if let expression = returned.expression {
        guard let parsed = RuntimeExpressionParser(syntax: syntax).parse(
          expression,
          diagnostics: &diagnostics
        )
        else { return nil }
        value = parsed
      } else {
        value = nil
      }
      return RuntimeStatement(kind: .return(value), location: location)
    case let .decl(declaration):
      guard let variable = declaration.as(VariableDeclSyntax.self),
            variable.bindingSpecifier.tokenKind == .keyword(.let),
            variable.bindings.count == 1,
            let binding = variable.bindings.first,
            let name = binding.pattern.as(IdentifierPatternSyntax.self)?
            .identifier.text,
            let expression = binding.initializer?.value,
            let value = RuntimeExpressionParser(syntax: syntax).parse(
              expression,
              diagnostics: &diagnostics
            )
      else {
        diagnostics.append(unsupported(item))
        return nil
      }
      let type: SupportedAPI.RuntimeType?
      if let annotation = binding.typeAnnotation {
        guard let parsedType = syntax.runtimeType(
          from: annotation.type,
          diagnostics: &diagnostics
        ) else { return nil }
        type = parsedType
      } else {
        type = nil
      }
      return RuntimeStatement(
        kind: .binding(
          name: name,
          type: type,
          value: value
        ),
        location: location
      )
    }
  }

  private func parse(
    _ conditional: IfExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeStatement? {
    guard conditional.conditions.count == 1,
          let element = conditional.conditions.first
    else {
      diagnostics.append(unsupported(conditional))
      return nil
    }
    guard let condition = parse(
      element.condition,
      diagnostics: &diagnostics
    )
    else {
      if diagnostics.isEmpty {
        diagnostics.append(unsupported(element))
      }
      return nil
    }
    guard let success = parse(
      conditional.body.statements,
      diagnostics: &diagnostics
    )
    else { return nil }
    let failure: RuntimeBody?
    switch conditional.elseBody {
    case nil:
      failure = nil
    case let .codeBlock(block):
      guard let body = parse(
        block.statements,
        diagnostics: &diagnostics
      )
      else { return nil }
      failure = body
    case let .ifExpr(nested):
      guard let statement = parse(nested, diagnostics: &diagnostics)
      else { return nil }
      failure = RuntimeBody(statements: [statement])
    }
    return RuntimeStatement(
      kind: .ifStatement(
        condition: condition,
        success: success,
        failure: failure
      ),
      location: syntax.location(of: conditional)
    )
  }

  private func parse(
    _ condition: ConditionElementSyntax.Condition,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeCondition? {
    switch condition {
    case let .expression(expression):
      return RuntimeExpressionParser(syntax: syntax).parse(
        expression,
        diagnostics: &diagnostics
      ).map(RuntimeCondition.boolean)
    case let .optionalBinding(binding):
      guard binding.bindingSpecifier.tokenKind == .keyword(.let),
            let name = binding.pattern.as(IdentifierPatternSyntax.self)?
            .identifier.text,
            let expression = binding.initializer?.value,
            let value = RuntimeExpressionParser(syntax: syntax).parse(
              expression,
              diagnostics: &diagnostics
            )
      else { return nil }
      return .optionalBinding(name: name, value: value)
    case .availability, .matchingPattern:
      return nil
    }
  }

  private func unsupported(_ node: some SyntaxProtocol) -> Diagnostic {
    syntax.error("portable rules do not support this statement", at: node)
  }
}
