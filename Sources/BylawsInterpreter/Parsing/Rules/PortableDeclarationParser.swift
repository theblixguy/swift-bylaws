import BylawsCore
import SwiftSyntax

struct PortableDeclarationParser {
  let syntax: RulesSyntaxContext

  func handles(_ variable: VariableDeclSyntax) -> Bool {
    guard let initializer = variable.bindings.first?.initializer?.value,
          let call = initializer.as(FunctionCallExprSyntax.self),
          let name = syntax.identifier(of: call.calledExpression)
    else { return true }
    return SupportedAPI.Value(rawValue: name) == nil
      || (name == "Layering" && call.trailingClosure != nil)
  }

  func parse(
    _ variable: VariableDeclSyntax,
    into parsed: inout ParsedRulesFile
  ) {
    guard variable.bindingSpecifier.tokenKind == .keyword(.let),
          let access = declarationAccess(variable.modifiers),
          variable.bindings.count == 1,
          let binding = variable.bindings.first,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)?
          .identifier.text,
          let initializer = binding.initializer?.value
    else {
      parsed.diagnostics.append(unsupported(variable))
      return
    }
    guard parsed.bindingNames.insert(name).inserted else {
      parsed.diagnostics.append(
        syntax.error("'\(name)' is declared twice", at: variable)
      )
      return
    }
    guard let expression = RuntimeExpressionParser(syntax: syntax).parse(
      initializer,
      diagnostics: &parsed.diagnostics
    )
    else { return }
    let type: SupportedAPI.RuntimeType?
    if let annotation = binding.typeAnnotation {
      guard let parsedType = syntax.runtimeType(
        from: annotation.type,
        diagnostics: &parsed.diagnostics
      ) else { return }
      type = parsedType
    } else {
      type = nil
    }
    parsed.runtimeBindings.append(
      RuntimeGlobalBinding(
        name: name,
        type: type,
        expression: expression,
        location: syntax.location(of: variable),
        access: access
      )
    )
    if isRuleCollection(
      name: name,
      binding: binding,
      initializer: initializer
    ) {
      parsed.runtimeRuleBindings.append(name)
    }
  }

  func parse(
    _ function: FunctionDeclSyntax,
    into parsed: inout ParsedRulesFile
  ) {
    let name = function.name.text
    guard function.genericParameterClause == nil,
          function.genericWhereClause == nil,
          let body = function.body,
          let returnClause = function.signature.returnClause,
          let access = declarationAccess(function.modifiers)
    else {
      parsed.diagnostics.append(unsupported(function))
      return
    }
    guard parsed.bindingNames.insert(name).inserted else {
      parsed.diagnostics.append(
        syntax.error("'\(name)' is declared twice", at: function)
      )
      return
    }
    guard function.signature.parameterClause.parameters.allSatisfy({
      $0.defaultValue == nil && $0.ellipsis == nil
        && !$0.type.trimmedDescription.hasPrefix("inout ")
        && !$0.type.trimmedDescription.hasPrefix("borrowing ")
        && !$0.type.trimmedDescription.hasPrefix("consuming ")
    })
    else {
      parsed.diagnostics.append(unsupported(function))
      return
    }
    var parameters: [RuntimeFunctionDefinition.Parameter] = []
    for parameter in function.signature.parameterClause.parameters {
      guard let type = syntax.runtimeType(
        from: parameter.type,
        diagnostics: &parsed.diagnostics
      ) else { return }
      parameters.append(RuntimeFunctionDefinition.Parameter(
        externalName: parameter.firstName.text == "_"
          ? nil : parameter.firstName.text,
        localName: parameter.secondName?.text ?? parameter.firstName.text,
        type: type
      ))
    }
    guard let returnType = syntax.runtimeType(
      from: returnClause.type,
      diagnostics: &parsed.diagnostics
    ) else { return }
    var diagnostics: [Diagnostic] = []
    guard let loweredBody = RuntimeStatementParser(syntax: syntax).parse(
      body.statements,
      diagnostics: &diagnostics
    )
    else {
      parsed.diagnostics.append(contentsOf: diagnostics)
      return
    }
    parsed.runtimeFunctions.append(
      RuntimeFunctionDefinition(
        name: name,
        parameters: parameters,
        returnType: returnType,
        isAsync: function.signature.effectSpecifiers?.asyncSpecifier != nil,
        isThrowing: function.signature.effectSpecifiers?.throwsClause != nil,
        body: loweredBody,
        location: syntax.location(of: function),
        access: access
      )
    )
  }

  private func isRuleCollection(
    name: String,
    binding: PatternBindingSyntax,
    initializer: ExprSyntax
  ) -> Bool {
    if binding.typeAnnotation?.type.trimmedDescription == "[Rule]" {
      return true
    }
    if name == RulesBindingName.rules.rawValue { return true }
    if let call = initializer.as(FunctionCallExprSyntax.self),
       call.trailingClosure != nil,
       syntax.identifier(of: call.calledExpression) == "Array"
       || call.calledExpression
       .trimmedDescription == "Array<Rule>" { return true }
    guard let array = initializer.as(ArrayExprSyntax.self) else { return false }
    let elements = array.elements
    guard !elements.isEmpty else { return false }
    return elements.allSatisfy { element in
      guard let call = element.expression.as(FunctionCallExprSyntax.self)
      else { return false }
      return syntax.identifier(of: call.calledExpression)
        == SupportedAPI.Declaration.rule.rawValue
    }
  }

  private func declarationAccess(
    _ modifiers: DeclModifierListSyntax
  ) -> RuntimeDeclarationAccess? {
    var access = RuntimeDeclarationAccess.module
    for modifier in modifiers {
      guard let supported = RuntimeDeclarationModifier(
        rawValue: modifier.name.text
      ) else { return nil }
      if supported == .public { access = .exported }
    }
    return access
  }

  private func unsupported(_ node: some SyntaxProtocol) -> Diagnostic {
    syntax.error("portable rules do not support this declaration", at: node)
  }
}

private enum RulesBindingName: String {
  case rules
}

private enum RuntimeDeclarationModifier: String {
  case `internal`
  case nonisolated
  case `public`
}
