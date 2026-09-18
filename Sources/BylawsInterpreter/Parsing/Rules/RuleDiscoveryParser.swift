import BylawsCore
import BylawsSyntax

struct RuleDiscoveryParser {
  let syntax: RulesSyntaxContext

  func parse(
    _ call: FunctionCallExprSyntax,
    into parsed: inout ParsedRulesFile
  ) {
    guard parsed.discovery == nil else {
      parsed.diagnostics.append(
        syntax.error(
          "RuleDiscovery must be declared once",
          at: call,
          hint: "combine the excluded folders in one declaration"
        )
      )
      return
    }
    parsed.discovery = (nil, syntax.location(of: call))
    guard call.trailingClosure == nil,
          call.additionalTrailingClosures.isEmpty
    else {
      parsed.diagnostics.append(
        syntax.error("RuleDiscovery takes no trailing closure", at: call)
      )
      return
    }
    guard call.arguments.count == 1,
          let argument = call.arguments.first,
          argument.label?.text == "excluding",
          let patterns = RulesStringDecoder.array(argument.expression)
    else {
      parsed.diagnostics.append(
        syntax.error(
          "RuleDiscovery takes an 'excluding' array of string literals",
          at: call,
          hint: "use RuleDiscovery(excluding: [\"Vendor\", \"**/Generated\"])"
        )
      )
      return
    }
    parsed.discovery?.value = RuleDiscovery(
      excluding: patterns.map { Glob($0) }
    )
  }
}
