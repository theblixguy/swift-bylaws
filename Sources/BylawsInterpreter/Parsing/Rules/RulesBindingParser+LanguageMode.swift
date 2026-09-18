import BylawsCore
import BylawsSyntax

extension RulesBindingParser {
  func parseLanguageMode(_ expression: ExprSyntax) -> Codebase.LanguageMode? {
    if let name = languageModeMember(expression) {
      return switch name {
      case "v4": .v4
      case "v5": .v5
      case "v6": .v6
      default: nil
      }
    }
    guard let call = expression.as(FunctionCallExprSyntax.self),
          languageModeMember(call.calledExpression) == "automatic",
          call.trailingClosure == nil,
          call.additionalTrailingClosures.isEmpty,
          call.arguments.count == 1,
          let argument = call.arguments.first,
          argument.label == nil
    else { return nil }

    let expressions = if let array = argument.expression
      .as(ArrayExprSyntax.self)
    { array.elements.map(\.expression) }
    else { [argument.expression] }
    var projects: Codebase.LanguageMode.Projects = []
    for expression in expressions {
      switch languageModeMember(expression) {
      case "swiftPM": projects.insert(.swiftPM)
      case "xcode": projects.insert(.xcode)
      default: return nil
      }
    }
    return .automatic(projects)
  }

  private func languageModeMember(_ expression: ExprSyntax) -> String? {
    guard let member = expression.as(MemberAccessExprSyntax.self),
          member.base == nil,
          member.declName.argumentNames == nil
    else { return nil }
    return member.declName.baseName.text
  }
}
