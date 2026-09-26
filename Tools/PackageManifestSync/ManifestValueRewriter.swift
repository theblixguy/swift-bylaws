import BylawsSyntax
import Foundation

final class ManifestValueRewriter: SyntaxRewriter {
  let pluginTool: PluginToolMetadata
  let configurations: [String: SwiftSyntaxMetadata]
  private(set) var pluginUpdates: [String: Int] = [:]
  private(set) var configurationUpdates: [String: [String: Int]] = [:]
  private(set) var compilerVersions: Set<String> = []
  private(set) var pluginEnumCount = 0
  private(set) var swiftVersionEnumCount = 0

  init(
    pluginTool: PluginToolMetadata,
    configurations: [String: SwiftSyntaxMetadata]
  ) {
    self.pluginTool = pluginTool
    self.configurations = configurations
    super.init()
  }

  override func visit(_ node: EnumDeclSyntax) -> DeclSyntax {
    if node.name.text == "PluginToolArtifact",
       enclosingEnumNames(of: node).isEmpty
    {
      pluginEnumCount += 1
    }
    if node.name.text == "SwiftVersion",
       enclosingEnumNames(of: node).first == "SwiftSyntaxArtifact"
    {
      swiftVersionEnumCount += 1
    }
    return super.visit(node)
  }

  override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
    guard enclosingEnumNames(of: node).first == "PluginToolArtifact",
          node.bindings.count == 1,
          let binding = node.bindings.first,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)?
          .identifier.text,
          let initializer = binding.initializer,
          let value = pluginValue(named: name)
    else {
      return super.visit(node)
    }

    var updatedBinding = binding
    updatedBinding.initializer = initializer.with(
      \.value,
      value.withTrivia(from: initializer.value)
    )
    var updated = node
    updated.bindings = [updatedBinding]
    pluginUpdates[name, default: 0] += 1
    return DeclSyntax(updated)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
    guard node.calledExpression.as(DeclReferenceExprSyntax.self)?
      .baseName.text == "SwiftSyntaxArtifactConfiguration",
      enclosingEnumNames(of: node).starts(with: [
        "SwiftVersion", "SwiftSyntaxArtifact",
      ]),
      let switchCase = enclosingSwitchCase(of: node),
      let name = compilerVersion(in: switchCase)
    else {
      return super.visit(node)
    }
    compilerVersions.insert(name)
    guard let configuration = configurations[name] else {
      return super.visit(node)
    }

    var updated = node
    updated.arguments = LabeledExprListSyntax(node.arguments.map { argument in
      guard let label = argument.label?.text,
            let value = configurationValue(
              named: label,
              from: configuration
            )
      else {
        return argument
      }
      var updatedArgument = argument
      updatedArgument.expression = value.withTrivia(from: argument.expression)
      configurationUpdates[name, default: [:]][label, default: 0] += 1
      return updatedArgument
    })
    return ExprSyntax(updated)
  }

  private func pluginValue(named name: String) -> ExprSyntax? {
    switch name {
    case "mode":
      .member(pluginTool.mode.rawValue)
    case "url":
      .optionalString(pluginTool.url)
    case "checksum":
      .optionalString(pluginTool.checksum)
    default:
      nil
    }
  }

  private func configurationValue(
    named name: String,
    from configuration: SwiftSyntaxMetadata
  ) -> ExprSyntax? {
    switch name {
    case "mode":
      .member(configuration.mode.rawValue)
    case "swiftCompilerVersion":
      .string(configuration.swiftCompilerVersion)
    case "swiftSyntaxVersion":
      .string(configuration.swiftSyntaxVersion)
    case "artifactRevision":
      ExprSyntax(IntegerLiteralExprSyntax(
        literal: .integerLiteral(String(configuration.artifactRevision))
      ))
    case "swiftArtifactChecksum":
      .optionalString(configuration.swiftArtifactChecksum)
    case "cArtifactChecksum":
      .optionalString(configuration.cArtifactChecksum)
    default:
      nil
    }
  }

  private func compilerVersion(in node: SwitchCaseSyntax) -> String? {
    guard case let .case(label) = node.label,
          label.caseItems.count == 1,
          let pattern = label.caseItems.first?.pattern
          .as(ExpressionPatternSyntax.self),
          let member = pattern.expression.as(MemberAccessExprSyntax.self)
    else {
      return nil
    }
    return member.declName.baseName.text
  }

  private func enclosingEnumNames(of node: some SyntaxProtocol) -> [String] {
    var names: [String] = []
    var parent = node.parent
    while let current = parent {
      if let declaration = current.as(EnumDeclSyntax.self) {
        names.append(declaration.name.text)
      }
      parent = current.parent
    }
    return names
  }

  private func enclosingSwitchCase(
    of node: some SyntaxProtocol
  ) -> SwitchCaseSyntax? {
    var parent = node.parent
    while let current = parent {
      if let switchCase = current.as(SwitchCaseSyntax.self) {
        return switchCase
      }
      parent = current.parent
    }
    return nil
  }
}

extension ExprSyntax {
  fileprivate static func member(_ name: String) -> Self {
    Self(MemberAccessExprSyntax(
      declName: DeclReferenceExprSyntax(baseName: .identifier(name))
    ))
  }

  fileprivate static func string(_ value: String) -> Self {
    let literal = String(reflecting: value)
    let content = String(literal.dropFirst().dropLast())
    return Self(StringLiteralExprSyntax(
      openingQuote: .stringQuoteToken(),
      segments: [
        .stringSegment(StringSegmentSyntax(
          content: .stringSegment(content)
        )),
      ],
      closingQuote: .stringQuoteToken()
    ))
  }

  fileprivate static func optionalString(_ value: String?) -> Self {
    value.map(string) ?? Self(NilLiteralExprSyntax())
  }

  fileprivate func withTrivia(from source: ExprSyntax) -> Self {
    with(\.leadingTrivia, source.leadingTrivia)
      .with(\.trailingTrivia, source.trailingTrivia)
  }
}
