import BylawsCore
import BylawsSyntax

struct RuleDeclarationParser {
  let syntax: RulesSyntaxContext

  func parse(
    _ call: FunctionCallExprSyntax,
    as keyword: SupportedAPI.Declaration,
    into parsed: inout ParsedRulesFile
  ) {
    let ruleLocation = syntax.location(of: call)
    guard call.additionalTrailingClosures.isEmpty else {
      parsed.diagnostics.append(
        .error(
          "\(keyword.rawValue) takes one trailing body closure",
          at: ruleLocation
        )
      )
      return
    }
    guard let arguments = parseArguments(
      of: call,
      as: keyword,
      diagnostics: &parsed.diagnostics
    ) else { return }

    if keyword == .override, arguments.reason == nil {
      parsed.diagnostics.append(
        .error(
          "Override takes a reason",
          at: ruleLocation,
          hint: "add a 'reason:' argument that describes the deviation"
        )
      )
      return
    }
    let expectedCounts = keyword == .override ? [1] : [1, 2]
    guard expectedCounts.contains(arguments.positional.count) else {
      parsed.diagnostics.append(
        .error(
          keyword == .override
            ? "Override takes one rule ID"
            : "Rule takes an ID and an optional display name",
          at: ruleLocation
        )
      )
      return
    }

    guard let closure = call.trailingClosure,
          closure.signature == nil,
          closure.statements.count == 1,
          let statement = closure.statements.first,
          case let .expr(bodyExpression) = statement.item
    else {
      parsed.diagnostics.append(
        .error(
          "a rule's body must be one query expression",
          at: ruleLocation,
          hint: "several statements or a closure parameter belong in a "
            + "test target"
        )
      )
      return
    }

    guard let body = RuleBodyParser(syntax: syntax)
      .parse(bodyExpression, diagnostics: &parsed.diagnostics)
    else { return }
    parsed.rules.append(
      ParsedRule(
        overrideReason: arguments.reason,
        id: arguments.positional.first,
        name: arguments.positional.count > 1
          ? arguments.positional[1] : arguments.positional[0],
        declaredEnforcement: arguments.enforcement,
        declaredHint: arguments.hint,
        location: ruleLocation,
        body: body
      )
    )
  }

  private struct Arguments {
    var positional: [String] = []
    var enforcement: Enforcement?
    var hint: String?
    var reason: String?
  }

  private func parseArguments(
    of call: FunctionCallExprSyntax,
    as keyword: SupportedAPI.Declaration,
    diagnostics: inout [Diagnostic]
  ) -> Arguments? {
    var arguments = Arguments()
    var argumentState = RulesArgumentState()
    for argument in call.arguments {
      guard case let .label(label) = argumentState.consumeArgumentLabel(
        of: argument,
        in: syntax,
        appendingDiagnosticsTo: &diagnostics
      ) else { return nil }
      switch label {
      case nil where argument.label == nil:
        guard !argumentState.sawLabelledArgument,
              let value = RulesStringDecoder.string(argument.expression)
        else {
          diagnostics.append(
            syntax.error(
              "\(keyword.rawValue) takes plain string literals here",
              at: argument,
              hint: "interpolation and computed values belong in a test "
                + "target"
            )
          )
          return nil
        }
        arguments.positional.append(value)
      case .enforcement:
        guard let member = syntax.memberName(of: argument.expression),
              let parsedEnforcement = Enforcement(rawValue: member)
        else {
          diagnostics.append(
            syntax.error(
              "'enforcement:' takes '.advisory' or '.enforced'",
              at: argument
            )
          )
          return nil
        }
        arguments.enforcement = parsedEnforcement
      case .hint:
        guard let value = RulesStringDecoder.string(argument.expression) else {
          diagnostics.append(
            syntax.error("'hint:' takes a plain string literal", at: argument)
          )
          return nil
        }
        arguments.hint = value
      case .reason where keyword == .override:
        guard let value = RulesStringDecoder.string(argument.expression) else {
          diagnostics.append(
            syntax.error("'reason:' takes a plain string literal", at: argument)
          )
          return nil
        }
        arguments.reason = value
      default:
        diagnostics.append(
          syntax.error(
            "\(keyword.rawValue) does not take "
              + "'\(argument.label?.text ?? "_")' here",
            at: argument
          )
        )
        return nil
      }
    }
    return arguments
  }
}
