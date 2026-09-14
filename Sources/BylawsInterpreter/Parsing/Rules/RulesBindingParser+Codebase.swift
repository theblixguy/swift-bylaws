import BylawsCore
import SwiftSyntax

extension RulesBindingParser {
  func parseCodebase(
    _ call: FunctionCallExprSyntax,
    into parsed: inout ParsedRulesFile
  ) -> Codebase? {
    guard hasNoTrailingClosure(
      call,
      named: SupportedAPI.Value.codebase.rawValue,
      into: &parsed
    )
    else {
      return nil
    }
    var including: [Glob] = []
    var excluding: [Glob] = []
    var swiftLanguageMode = Codebase.LanguageMode.automatic(.swiftPM)
    var root: Codebase.Root = .directory(parsed.directory)
    var argumentState = RulesArgumentState()
    for argument in call.arguments {
      guard case let .label(label) = argumentState.consumeArgumentLabel(
        of: argument,
        in: syntax,
        appendingDiagnosticsTo: &parsed.diagnostics
      ) else { return nil }
      switch label {
      case .swiftLanguageMode:
        guard let mode = parseLanguageMode(argument.expression)
        else {
          parsed.diagnostics.append(syntax.error(
            "Codebase takes .v4, .v5, .v6 or .automatic(...) for swiftLanguageMode",
            at: argument,
            hint: "Use .automatic(.swiftPM), .automatic(.xcode) or .automatic([.swiftPM, .xcode]) to read project settings"
          ))
          return nil
        }
        swiftLanguageMode = mode
      case .including:
        guard let patterns = RulesStringDecoder.array(argument.expression)
        else {
          parsed.diagnostics.append(
            malformedCodebaseArgument("including", argument)
          )
          return nil
        }
        including = patterns.map { Glob($0) }
      case .excluding:
        guard let patterns = RulesStringDecoder.array(argument.expression)
        else {
          parsed.diagnostics.append(
            malformedCodebaseArgument("excluding", argument)
          )
          return nil
        }
        excluding = patterns.map { Glob($0) }
      case .root:
        guard let parsedRoot = parseRoot(argument.expression, file: parsed)
        else {
          parsed.diagnostics.append(
            syntax.error(
              "'root:' takes '.automatic()' or '.directory(\"path\")'",
              at: argument
            )
          )
          return nil
        }
        root = parsedRoot
      default:
        parsed.diagnostics.append(
          syntax.error(
            "Codebase takes root, including, excluding and swiftLanguageMode",
            at: argument
          )
        )
        return nil
      }
    }
    return Codebase(
      root: root,
      including: including,
      excluding: excluding,
      swiftLanguageMode: swiftLanguageMode
    )
  }

  private func parseRoot(
    _ expression: ExprSyntax,
    file: ParsedRulesFile
  ) -> Codebase.Root? {
    guard let call = expression.as(FunctionCallExprSyntax.self),
          call.trailingClosure == nil,
          call.additionalTrailingClosures.isEmpty,
          let member = call.calledExpression.as(MemberAccessExprSyntax.self),
          member.base == nil
    else { return nil }
    guard let root = SupportedAPI.CodebaseRoot(
      rawValue: member.declName.baseName.text
    )
    else { return nil }
    switch root {
    case .automatic where call.arguments.isEmpty:
      return .automatic(above: file.path)
    case .directory where call.arguments.count == 1:
      guard let argument = call.arguments.first,
            argument.label == nil,
            let path = RulesStringDecoder.string(argument.expression)
      else { return nil }
      return .directory(path)
    default:
      return nil
    }
  }

  private func malformedCodebaseArgument(
    _ label: String,
    _ argument: LabeledExprSyntax
  ) -> Diagnostic {
    syntax.error(
      "'\(label)' takes an array of glob pattern literals",
      at: argument
    )
  }
}
