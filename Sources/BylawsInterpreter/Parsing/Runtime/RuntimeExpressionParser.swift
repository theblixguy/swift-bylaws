import SwiftParser
import SwiftSyntax

struct RuntimeExpressionParser {
  let syntax: RulesSyntaxContext

  func parse(
    _ expression: ExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeExpression? {
    let location = syntax.location(of: expression)

    if let tried = expression.as(TryExprSyntax.self) {
      guard tried.questionOrExclamationMark == nil else {
        diagnostics.append(unsupported(tried))
        return nil
      }
      return parse(tried.expression, diagnostics: &diagnostics)
    }
    if let awaited = expression.as(AwaitExprSyntax.self) {
      return parse(awaited.expression, diagnostics: &diagnostics)
    }
    if let literal = expression.as(StringLiteralExprSyntax.self) {
      return parseString(literal, diagnostics: &diagnostics)
    }
    if let literal = expression.as(IntegerLiteralExprSyntax.self),
       let value = Int(literal.literal.text)
    {
      return RuntimeExpression(kind: .integer(value), location: location)
    }
    if let literal = expression.as(FloatLiteralExprSyntax.self),
       let value = Double(literal.literal.text)
    {
      return RuntimeExpression(kind: .double(value), location: location)
    }
    if let literal = expression.as(BooleanLiteralExprSyntax.self) {
      return RuntimeExpression(
        kind: .boolean(literal.literal.tokenKind == .keyword(.true)),
        location: location
      )
    }
    if expression.is(NilLiteralExprSyntax.self) {
      return RuntimeExpression(kind: .nilLiteral, location: location)
    }
    if let chained = expression.as(OptionalChainingExprSyntax.self) {
      return parse(chained.expression, diagnostics: &diagnostics)
    }
    if let array = expression.as(ArrayExprSyntax.self) {
      return parseArray(array, diagnostics: &diagnostics)
    }
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
      return RuntimeExpression(
        kind: .reference(reference.baseName.text),
        location: location
      )
    }
    if let member = expression.as(MemberAccessExprSyntax.self) {
      return parseMemberAccess(member, diagnostics: &diagnostics)
    }
    if let generic = expression.as(GenericSpecializationExprSyntax.self) {
      return parseGenericSpecialization(generic, diagnostics: &diagnostics)
    }
    if let call = expression.as(FunctionCallExprSyntax.self) {
      return parseCall(call, diagnostics: &diagnostics)
    }
    if let subscriptCall = expression.as(SubscriptCallExprSyntax.self),
       subscriptCall.arguments.count == 1,
       let argument = subscriptCall.arguments.first,
       argument.label == nil,
       subscriptCall.trailingClosure == nil,
       subscriptCall.additionalTrailingClosures.isEmpty,
       let base = parse(
         subscriptCall.calledExpression,
         diagnostics: &diagnostics
       ),
       let key = parse(argument.expression, diagnostics: &diagnostics)
    {
      return RuntimeExpression(
        kind: .subscriptCall(base: base, key: key),
        location: location
      )
    }
    if let closure = expression.as(ClosureExprSyntax.self),
       let definition = parseClosure(closure, diagnostics: &diagnostics)
    {
      return RuntimeExpression(kind: .closure(definition), location: location)
    }
    if let infix = expression.as(InfixOperatorExprSyntax.self),
       let operatorExpression = infix.operator
       .as(BinaryOperatorExprSyntax.self),
       let left = parse(infix.leftOperand, diagnostics: &diagnostics),
       let right = parse(infix.rightOperand, diagnostics: &diagnostics)
    {
      return RuntimeExpression(
        kind: .binary(
          left: left,
          operator: operatorExpression.operator.text,
          right: right
        ),
        location: location
      )
    }
    if let prefix = expression.as(PrefixOperatorExprSyntax.self),
       let value = parse(prefix.expression, diagnostics: &diagnostics)
    {
      return RuntimeExpression(
        kind: .prefix(operator: prefix.operator.text, value),
        location: location
      )
    }
    if let tuple = expression.as(TupleExprSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first,
       element.label == nil
    {
      return parse(element.expression, diagnostics: &diagnostics)
    }
    if let keyPath = expression.as(KeyPathExprSyntax.self),
       let components = keyPathComponents(keyPath),
       let members = members(in: components)
    {
      return RuntimeExpression(
        kind: .keyPath(members),
        location: location
      )
    }

    diagnostics.append(unsupported(expression))
    return nil
  }

  func parseClosure(
    _ closure: ClosureExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeClosureDefinition? {
    guard closure.signature?.capture == nil else {
      diagnostics.append(unsupported(closure))
      return nil
    }
    let parameters: [String] =
      switch closure.signature?.parameterClause {
      case nil:
        []
      case let .simpleInput(input):
        input.map(\.name.text)
      case let .parameterClause(clause):
        clause.parameters.map {
          $0.secondName?.text ?? $0.firstName.text
        }
      }
    guard let body = RuntimeStatementParser(syntax: syntax).parse(
      closure.statements,
      diagnostics: &diagnostics
    )
    else { return nil }
    let effects = ClosureEffects(viewMode: .sourceAccurate)
    effects.walk(closure.statements)
    return RuntimeClosureDefinition(
      parameters: parameters,
      body: body,
      location: syntax.location(of: closure),
      usesAwait: effects.usesAwait || closure.signature?.effectSpecifiers?
        .asyncSpecifier != nil,
      usesTry: effects.usesTry || closure.signature?.effectSpecifiers?
        .throwsClause != nil
    )
  }

  private func parseArray(
    _ array: ArrayExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeExpression? {
    var elements: [RuntimeExpression] = []
    for element in array.elements {
      guard let value = parse(element.expression, diagnostics: &diagnostics)
      else { return nil }
      elements.append(value)
    }
    return RuntimeExpression(
      kind: .array(elements),
      location: syntax.location(of: array)
    )
  }

  private func parseMemberAccess(
    _ member: MemberAccessExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeExpression? {
    let location = syntax.location(of: member)
    let writtenName = member.declName.baseName.text
    guard let baseSyntax = member.base else {
      if writtenName == "init" {
        return RuntimeExpression(kind: .implicitConstructor, location: location)
      }
      guard let literal = SupportedAPI.MemberLiteral(rawValue: writtenName)
      else {
        diagnostics.append(unknownMemberLiteral(writtenName, at: member))
        return nil
      }
      return RuntimeExpression(
        kind: .staticMember(literal),
        location: location
      )
    }
    guard let base = parse(baseSyntax, diagnostics: &diagnostics) else {
      return nil
    }
    guard let name = SupportedAPI.Member(rawValue: writtenName) else {
      diagnostics.append(unsupported(member))
      return nil
    }
    return RuntimeExpression(
      kind: .member(base: base, name: name),
      location: location
    )
  }

  private func parseGenericSpecialization(
    _ generic: GenericSpecializationExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeExpression? {
    guard let base = parse(generic.expression, diagnostics: &diagnostics)
    else { return nil }
    var types: [SupportedAPI.RuntimeType] = []
    for argument in generic.genericArgumentClause.arguments {
      guard case let .type(typeSyntax) = argument.argument else {
        diagnostics.append(unsupported(generic))
        return nil
      }
      guard let type = syntax.runtimeType(
        from: typeSyntax,
        diagnostics: &diagnostics
      ) else { return nil }
      types.append(type)
    }
    return RuntimeExpression(
      kind: .generic(base: base, arguments: types),
      location: syntax.location(of: generic)
    )
  }

  private func parseCall(
    _ call: FunctionCallExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeExpression? {
    guard call.additionalTrailingClosures.isEmpty,
          let callee = parse(
            call.calledExpression,
            diagnostics: &diagnostics
          )
    else {
      diagnostics.append(unsupported(call))
      return nil
    }
    var arguments: [RuntimeCallArgument] = []
    for argument in call.arguments {
      guard let value = parse(
        argument.expression,
        diagnostics: &diagnostics
      )
      else { return nil }
      arguments.append(
        RuntimeCallArgument(label: argument.label?.text, value: value)
      )
    }
    let trailingClosure: RuntimeClosureDefinition?
    if let closure = call.trailingClosure {
      guard let parsed = parseClosure(closure, diagnostics: &diagnostics)
      else { return nil }
      trailingClosure = parsed
    } else {
      trailingClosure = nil
    }
    return RuntimeExpression(
      kind: .call(
        callee: callee,
        arguments: arguments,
        trailingClosure: trailingClosure
      ),
      location: syntax.location(of: call)
    )
  }

  private func parseString(
    _ literal: StringLiteralExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> RuntimeExpression? {
    let location = syntax.location(of: literal)
    if let value = literal.representedLiteralValue {
      return RuntimeExpression(kind: .string(value), location: location)
    }
    var segments: [RuntimeStringSegment] = []
    for segment in literal.segments {
      if let text = segment.as(StringSegmentSyntax.self) {
        segments.append(.text(text.content.text))
      } else if let interpolation = segment.as(ExpressionSegmentSyntax.self),
                interpolation.expressions.count == 1,
                let expression = interpolation.expressions.first?.expression,
                let value = parse(expression, diagnostics: &diagnostics)
      {
        segments.append(.expression(value))
      } else {
        diagnostics.append(unsupported(segment))
        return nil
      }
    }
    return RuntimeExpression(
      kind: .interpolatedString(segments),
      location: location
    )
  }

  private func keyPathComponents(_ keyPath: KeyPathExprSyntax) -> [String]? {
    guard keyPath.root == nil else { return nil }
    let text = keyPath.trimmedDescription
    guard text.hasPrefix("\\.") else { return nil }
    let components = text.dropFirst(2).split(separator: ".").map(String.init)
    return components.isEmpty ? nil : components
  }

  private func members(in names: [String]) -> [SupportedAPI.Member]? {
    let members = names.compactMap(SupportedAPI.Member.init(rawValue:))
    return members.count == names.count ? members : nil
  }

  // The evaluator compares member values as plain strings. A misspelt
  // literal answers false and the rule passes.
  private func unknownMemberLiteral(
    _ name: String,
    at node: some SyntaxProtocol
  ) -> Diagnostic {
    syntax.error(
      "'.\(name)' is not a supported member literal",
      at: node,
      hint: Self.closestMemberLiterals(to: name).map {
        "use \($0.map { ".\($0)" }.joined(separator: " or "))"
      }
    )
  }

  private static func closestMemberLiterals(to name: String) -> [String]? {
    let close = SupportedAPI.memberLiteralNames
      .filter {
        $0.lowercased() == name.lowercased() || isOneEditApart($0, name)
      }
      .sorted()
    return close.isEmpty ? nil : Array(close.prefix(3))
  }

  private static func isOneEditApart(_ left: String, _ right: String) -> Bool {
    let shorter = Array(left.count <= right.count ? left : right)
    let longer = Array(left.count <= right.count ? right : left)
    guard longer.count - shorter.count <= 1 else { return false }

    var shorterIndex = 0
    var longerIndex = 0
    var edited = false
    while shorterIndex < shorter.count, longerIndex < longer.count {
      guard shorter[shorterIndex] != longer[longerIndex] else {
        shorterIndex += 1
        longerIndex += 1
        continue
      }
      guard !edited else { return false }
      edited = true
      if shorter.count == longer.count { shorterIndex += 1 }
      longerIndex += 1
    }
    return true
  }

  private func unsupported(_ node: some SyntaxProtocol) -> Diagnostic {
    syntax.error("portable rules do not support this expression", at: node)
  }
}
