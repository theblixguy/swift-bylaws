import BylawsSyntax

struct RuleBodyParser {
  let syntax: RulesSyntaxContext

  func parse(
    _ expression: ExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> BodyExpression? {
    let finder = TrailingClosureFinder(viewMode: .sourceAccurate)
    finder.walk(expression)
    if let invalidCall = finder.calls.first {
      let name =
        invalidCall.calledExpression
          .as(MemberAccessExprSyntax.self)?.declName.baseName.text
          ?? "call"
      diagnostics.append(
        syntax.error("'\(name)' takes no trailing closure", at: invalidCall)
      )
      return nil
    }

    let expression = expressionWithoutEffectMarkers(expression)
    guard let chain = chain(of: expression) else {
      diagnostics.append(
        syntax.error(
          "a rule's body must be a chain from a codebase binding "
            + "to 'violations'",
          at: expression
        )
      )
      return nil
    }

    if chain.links.count == 1, let call = chain.links.first,
       call.name == "checkFolderLayout"
    {
      guard call.arguments.count == 2,
            call.arguments[0].hasLabel(.matching),
            case let .string(pattern) = call.arguments[0].value,
            call.arguments[1].hasLabel(.containing),
            case let .strings(folders) = call.arguments[1].value
      else {
        diagnostics.append(.error(
          "checkFolderLayout takes a string after 'matching:' and a string array after 'containing:'",
          at: call.location
        ))
        return nil
      }
      return .folderLayout(
        codebase: chain.base,
        pattern: pattern,
        folders: folders
      )
    }
    if chain.links.count == 1, let call = chain.links.first,
       call.name == "checkLayering", call.arguments.count == 1,
       call.arguments[0].label == nil,
       case let .reference(binding) = call.arguments[0].value
    {
      return .layeringCheck(codebase: chain.base, layering: binding)
    }
    if chain.links.count == 1,
       let manifestCheck = chain.links.first,
       let operation = SupportedAPI.CodebaseOperation(
         rawValue: manifestCheck.name
       )
    {
      return manifestBody(
        for: operation,
        calledBy: manifestCheck,
        over: chain.base,
        diagnostics: &diagnostics
      )
    }
    return queryBody(
      of: chain,
      in: expression,
      diagnostics: &diagnostics
    )
  }

  private func manifestBody(
    for operation: SupportedAPI.CodebaseOperation,
    calledBy call: ParsedCall,
    over codebase: String,
    diagnostics: inout [Diagnostic]
  ) -> BodyExpression? {
    if operation == .importGraph {
      diagnostics.append(
        .error(
          "'importGraph' returns an import graph, not violations",
          at: call.location,
          hint: "read the import graph in a test target"
        )
      )
      return nil
    }
    guard call.accepts(operation.arguments) else {
      diagnostics.append(
        .error(
          "'\(call.name)' " + operation.arguments.requirement,
          at: call.location
        )
      )
      return nil
    }
    let ignoredTargets = call.arguments.first?.value.stringValues ?? []
    return if operation == .checkPackageDependencies {
      .packageDependencies(
        codebase: codebase,
        ignoredTargets: ignoredTargets
      )
    } else {
      .dependencyStability(
        codebase: codebase,
        ignoredTargets: ignoredTargets
      )
    }
  }

  private func queryBody(
    of chain: (base: String, links: [ParsedCall]),
    in expression: ExprSyntax,
    diagnostics: inout [Diagnostic]
  ) -> BodyExpression? {
    guard let last = chain.links.last,
          last.name == SupportedAPI.SelectionOperation.violations.rawValue,
          let violationsArgument = last.arguments.first,
          last.arguments.count == 1
    else {
      diagnostics.append(
        syntax.error(
          "a rule's body must end in 'violations(of:)' or "
            + "'violations(matching:)'",
          at: expression
        )
      )
      return nil
    }

    let matcher: MatcherExpression? =
      violationsArgument.matcher
        ?? {
          guard case let .member(name) = violationsArgument.value else {
            return nil
          }
          return .leaf(
            ParsedCall(name: name, arguments: [], location: last.location)
          )
        }()
    let check: Check?
    if violationsArgument.hasLabel(.outsidePaths),
       violationsArgument.value.isString || violationsArgument.value
       .isStringArray
    {
      check = .outsidePaths(violationsArgument.value.stringValues)
    } else if let matcher {
      check = switch violationsArgument.label {
      case .of: .of(matcher)
      case .matching: .matching(matcher)
      default: nil
      }
    } else {
      diagnostics.append(
        .error(
          "'violations' takes a matcher or path patterns after 'outsidePaths:'",
          at: last.location,
          hint: "closures and custom matchers belong in a test target"
        )
      )
      return nil
    }
    guard let check else {
      diagnostics.append(
        .error(
          "'violations' takes 'of:', 'matching:' or 'outsidePaths:'",
          at: last.location
        )
      )
      return nil
    }

    guard let accessor = chain.links.first else {
      diagnostics.append(
        syntax.error(
          "the chain must start with a query, such as '.classes'",
          at: expression
        )
      )
      return nil
    }
    return .query(
      QueryExpression(
        codebase: chain.base,
        accessor: accessor,
        filters: Array(chain.links.dropFirst().dropLast()),
        check: check
      )
    )
  }

  private func expressionWithoutEffectMarkers(
    _ original: ExprSyntax
  ) -> ExprSyntax {
    var expression = original
    while true {
      if let tried = expression.as(TryExprSyntax.self) {
        expression = tried.expression
      } else if let awaited = expression.as(AwaitExprSyntax.self) {
        expression = awaited.expression
      } else {
        return expression
      }
    }
  }

  private func chain(of expression: ExprSyntax)
    -> (base: String, links: [ParsedCall])?
  {
    var links: [ParsedCall] = []
    var current = expression
    while true {
      if let call = current.as(FunctionCallExprSyntax.self),
         let member = call.calledExpression.as(MemberAccessExprSyntax.self),
         let base = member.base
      {
        guard let arguments = arguments(of: call) else { return nil }
        links.append(
          ParsedCall(
            name: member.declName.baseName.text,
            arguments: arguments,
            location: syntax.location(of: call)
          )
        )
        current = base
      } else if let member = current.as(MemberAccessExprSyntax.self),
                let base = member.base
      {
        links.append(
          ParsedCall(
            name: member.declName.baseName.text,
            arguments: [],
            location: syntax.location(of: member)
          )
        )
        current = base
      } else if let reference = current.as(DeclReferenceExprSyntax.self) {
        return (reference.baseName.text, links: links.reversed())
      } else {
        return nil
      }
    }
  }

  private func matcherExpression(_ expression: ExprSyntax)
    -> MatcherExpression?
  {
    if let infix = expression.as(InfixOperatorExprSyntax.self),
       let operatorToken = infix.operator.as(BinaryOperatorExprSyntax.self)
    {
      guard let left = matcherExpression(infix.leftOperand),
            let right = matcherExpression(infix.rightOperand)
      else { return nil }
      switch operatorToken.operator.text {
      case "&&": return .and(left, right)
      case "||": return .or(left, right)
      default: return nil
      }
    }
    if let prefix = expression.as(PrefixOperatorExprSyntax.self),
       prefix.operator.text == "!"
    {
      guard let inner = matcherExpression(prefix.expression) else {
        return nil
      }
      return .not(inner)
    }
    if let tuple = expression.as(TupleExprSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first,
       element.label == nil
    {
      return matcherExpression(element.expression)
    }
    if let member = expression.as(MemberAccessExprSyntax.self),
       member.base == nil
    {
      return .leaf(
        ParsedCall(
          name: member.declName.baseName.text,
          arguments: [],
          location: syntax.location(of: member)
        )
      )
    }
    if let call = expression.as(FunctionCallExprSyntax.self),
       let member = call.calledExpression.as(MemberAccessExprSyntax.self),
       member.base == nil,
       let arguments = arguments(of: call)
    {
      return .leaf(
        ParsedCall(
          name: member.declName.baseName.text,
          arguments: arguments,
          location: syntax.location(of: call)
        )
      )
    }
    return nil
  }

  private func arguments(of call: FunctionCallExprSyntax)
    -> [ParsedCall.Argument]?
  {
    var arguments: [ParsedCall.Argument] = []
    for argument in call.arguments {
      let value: LiteralValue? =
        if let text =
        RulesStringDecoder
          .string(argument.expression)
        {
          .string(text)
        } else if let texts = RulesStringDecoder.array(argument.expression) {
          .strings(texts)
        } else if let name = syntax.identifier(of: argument.expression) {
          .reference(name)
        } else if let member = syntax.memberName(of: argument.expression) {
          .member(member)
        } else if let matcher = matcherExpression(argument.expression) {
          .matcher(matcher)
        } else {
          nil
        }
      guard let value else { return nil }
      arguments.append(
        ParsedCall.Argument(rawLabel: argument.label?.text, value: value)
      )
    }
    return arguments
  }
}

private final class TrailingClosureFinder: SyntaxVisitor {
  private(set) var calls: [FunctionCallExprSyntax] = []

  override func visit(_ node: FunctionCallExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    if node.trailingClosure != nil || !node.additionalTrailingClosures.isEmpty {
      calls.append(node)
    }
    return .visitChildren
  }
}
