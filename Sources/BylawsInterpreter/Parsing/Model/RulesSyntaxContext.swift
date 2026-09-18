import BylawsSemantics
import BylawsSyntax

struct RulesSyntaxContext {
  let path: String
  let converter: SourceLocationConverter

  var startOfFile: DeclarationLocation {
    DeclarationLocation.start(of: path)
  }

  func identifier(of expression: ExprSyntax) -> String? {
    expression.as(DeclReferenceExprSyntax.self)?.baseName.text
  }

  func memberName(of expression: ExprSyntax) -> String? {
    guard let member = expression.as(MemberAccessExprSyntax.self),
          member.base == nil
    else { return nil }
    return member.declName.baseName.text
  }

  func location(of node: some SyntaxProtocol) -> DeclarationLocation {
    DeclarationLocation(of: node, converter: converter, filePath: path)
  }

  func error(
    _ message: String,
    at node: some SyntaxProtocol,
    hint: String? = nil
  ) -> Diagnostic {
    .error(message, at: location(of: node), hint: hint)
  }
}

struct RulesArgumentState {
  // A repeated label stops the caller reading arguments.
  enum LabelLookup {
    case label(SupportedAPI.ArgumentLabel?)
    case repeated
  }

  private var labels: Set<String> = []
  private(set) var sawLabelledArgument = false

  mutating func consumeArgumentLabel(
    of argument: LabeledExprSyntax,
    in syntax: RulesSyntaxContext,
    appendingDiagnosticsTo diagnostics: inout [Diagnostic]
  ) -> LabelLookup {
    guard let label = argument.label?.text else { return .label(nil) }
    guard labels.insert(label).inserted else {
      diagnostics.append(
        syntax.error("'\(label)' appears more than once", at: argument)
      )
      return .repeated
    }
    sawLabelledArgument = true
    return .label(SupportedAPI.ArgumentLabel(rawValue: label))
  }
}
