import BylawsCore
import SwiftSyntax

struct RulesBindingParser {
  let syntax: RulesSyntaxContext

  func parse(
    _ variable: VariableDeclSyntax,
    into parsed: inout ParsedRulesFile
  ) {
    guard variable.bindingSpecifier.tokenKind == .keyword(.let),
          let binding = variable.bindings.first,
          variable.bindings.count == 1,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)?
          .identifier.text,
          let value = binding.initializer?.value
          .as(FunctionCallExprSyntax.self),
          let callee = syntax.identifier(of: value.calledExpression),
          let keyword = SupportedAPI.Value(rawValue: callee)
    else {
      parsed.diagnostics.append(
        syntax.error(
          "a binding here must start with 'let name = Codebase(' or "
            + "'let name = Layering('",
          at: variable
        )
      )
      return
    }

    guard parsed.bindingNames.insert(name).inserted else {
      parsed.diagnostics.append(
        syntax.error("'\(name)' is declared twice", at: variable)
      )
      return
    }

    switch keyword {
    case .codebase:
      if let codebase = parseCodebase(value, into: &parsed) {
        parsed.codebases[name] = codebase
      }
    case .layering:
      if let layering = parseLayering(value, into: &parsed) {
        parsed.layerings[name] = layering
      }
    case .layer:
      parsed.diagnostics.append(
        syntax.error(
          "a Layer belongs inside a Layering",
          at: value,
          hint: "bind the Layering and pass the Layer values to it"
        )
      )
    }
  }

  private func parseLayering(
    _ call: FunctionCallExprSyntax,
    into parsed: inout ParsedRulesFile
  ) -> Layering? {
    guard hasNoTrailingClosure(
      call,
      named: SupportedAPI.Value.layering.rawValue,
      into: &parsed
    )
    else {
      return nil
    }
    var layers: [Layer] = []
    for argument in call.arguments {
      guard argument.label == nil,
            let layerCall = argument.expression
            .as(FunctionCallExprSyntax.self),
            syntax.identifier(of: layerCall.calledExpression)
            == SupportedAPI.Value.layer.rawValue,
            let layer = parseLayer(layerCall, into: &parsed)
      else {
        parsed.diagnostics.append(
          syntax.error("Layering takes Layer values", at: argument)
        )
        return nil
      }
      layers.append(layer)
    }
    return Layering(layers)
  }

  private func parseLayer(
    _ call: FunctionCallExprSyntax,
    into parsed: inout ParsedRulesFile
  ) -> Layer? {
    guard hasNoTrailingClosure(
      call,
      named: SupportedAPI.Value.layer.rawValue,
      into: &parsed
    )
    else {
      return nil
    }
    var name: String?
    var files: [Glob] = []
    var modules: [String]?
    var mayImport: Layer.ImportPolicy = .only([])
    var mustImport: [String] = []
    var mustNotImport: [String] = []
    var argumentState = RulesArgumentState()
    for argument in call.arguments {
      guard case let .label(label) = argumentState.consumeArgumentLabel(
        of: argument,
        in: syntax,
        appendingDiagnosticsTo: &parsed.diagnostics
      ) else { return nil }
      switch label {
      case nil where argument.label == nil:
        guard name == nil, !argumentState.sawLabelledArgument,
              let value = RulesStringDecoder.string(argument.expression)
        else {
          parsed.diagnostics.append(
            syntax.error("Layer takes one unlabelled name", at: argument)
          )
          return nil
        }
        name = value
      case .files:
        guard let patterns = RulesStringDecoder.array(argument.expression)
        else {
          parsed.diagnostics.append(
            malformedLayerArgument("files", "glob patterns", argument)
          )
          return nil
        }
        files = patterns.map { Glob($0) }
      case .modules:
        guard let names = RulesStringDecoder.array(argument.expression) else {
          parsed.diagnostics.append(
            malformedLayerArgument("modules", "module names", argument)
          )
          return nil
        }
        modules = names
      case .mayImport:
        if isAnyImportPolicy(argument.expression) {
          mayImport = .any
        } else if let names = RulesStringDecoder.array(argument.expression) {
          mayImport = .only(names)
        } else {
          parsed.diagnostics.append(
            syntax.error(
              "'mayImport' takes an array of layer names or '.any'",
              at: argument
            )
          )
          return nil
        }
      case .mustImport:
        guard let names = RulesStringDecoder.array(argument.expression) else {
          parsed.diagnostics.append(
            malformedLayerArgument("mustImport", "layer names", argument)
          )
          return nil
        }
        mustImport = names
      case .mustNotImport:
        guard let names = RulesStringDecoder.array(argument.expression) else {
          parsed.diagnostics.append(
            malformedLayerArgument("mustNotImport", "layer names", argument)
          )
          return nil
        }
        mustNotImport = names
      default:
        parsed.diagnostics.append(
          syntax.error(
            "Layer does not take "
              + "'\(argument.label?.text ?? "_")' here",
            at: argument
          )
        )
        return nil
      }
    }
    guard let name else {
      parsed.diagnostics.append(
        syntax.error("Layer takes one unlabelled name", at: call)
      )
      return nil
    }
    return Layer(
      name,
      files: files,
      modules: modules,
      mayImport: mayImport,
      mustImport: mustImport,
      mustNotImport: mustNotImport
    )
  }

  private func isAnyImportPolicy(_ expression: ExprSyntax) -> Bool {
    guard let member = expression.as(MemberAccessExprSyntax.self) else {
      return false
    }
    return member.base == nil
      && member.declName.baseName.text
      == SupportedAPI.LayerImportPolicy.any.rawValue
  }

  private func malformedLayerArgument(
    _ label: String,
    _ contents: String,
    _ argument: LabeledExprSyntax
  ) -> Diagnostic {
    syntax.error("'\(label)' takes an array of \(contents)", at: argument)
  }

  func hasNoTrailingClosure(
    _ call: FunctionCallExprSyntax,
    named name: String,
    into parsed: inout ParsedRulesFile
  ) -> Bool {
    guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty
    else {
      parsed.diagnostics.append(
        syntax.error("\(name) takes no trailing closure", at: call)
      )
      return false
    }
    return true
  }
}
