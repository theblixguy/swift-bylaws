import BylawsCore
import BylawsSemantics
import BylawsSyntax

struct BaselineFileParser {
  let path: String
  let converter: SourceLocationConverter

  static func parse(
    source: String,
    path: String
  ) -> Result<[Baseline.Entry], Diagnostic> {
    let tree = Parser.parse(source: source)
    let parser = BaselineFileParser(
      path: path,
      converter: SourceLocationConverter(fileName: path, tree: tree)
    )
    guard !tree.hasError else { return .failure(parser.syntaxError(in: tree)) }
    return parser.entries(in: tree)
  }

  private func entries(
    in tree: SourceFileSyntax
  ) -> Result<[Baseline.Entry], Diagnostic> {
    let statements = Array(tree.statements)
    guard statements.count == 2,
          let importDeclaration = declaration(
            statements[0],
            as: ImportDeclSyntax.self
          ),
          importsBylaws(importDeclaration),
          let baselineExtension = declaration(
            statements[1],
            as: ExtensionDeclSyntax.self
          ),
          isBaselineExtension(baselineExtension),
          let variable = baselineVariable(in: baselineExtension),
          let binding = variable.bindings.first,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)?
          .identifier.text,
          BaselineFile.isValidIdentifier(name),
          let value = binding.initializer?.value
          .as(FunctionCallExprSyntax.self),
          let entries = entries(in: value, named: name)
    else { return .failure(malformedFile(at: tree)) }
    return entries
  }

  private func declaration<Declaration: DeclSyntaxProtocol>(
    _ item: CodeBlockItemSyntax,
    as type: Declaration.Type
  ) -> Declaration? {
    guard case let .decl(declaration) = item.item else { return nil }
    return declaration.as(type)
  }

  private func importsBylaws(_ declaration: ImportDeclSyntax) -> Bool {
    declaration.attributes.isEmpty
      && declaration.modifiers.isEmpty
      && declaration.importKindSpecifier == nil
      && declaration.path.count == 1
      && declaration.path.first?.name.text == "Bylaws"
  }

  private func isBaselineExtension(_ declaration: ExtensionDeclSyntax) -> Bool {
    declaration.attributes.isEmpty
      && declaration.modifiers.isEmpty
      && declaration.extendedType.as(IdentifierTypeSyntax.self)?.name.text
      == "Baseline"
      && declaration.inheritanceClause == nil
      && declaration.genericWhereClause == nil
      && declaration.memberBlock.members.count == 1
  }

  private func baselineVariable(
    in declaration: ExtensionDeclSyntax
  ) -> VariableDeclSyntax? {
    guard let member = declaration.memberBlock.members.first?.decl
      .as(VariableDeclSyntax.self),
      member.attributes.isEmpty,
      member.modifiers.count == 1,
      member.modifiers.first?.name.tokenKind == .keyword(.static),
      member.bindingSpecifier.tokenKind == .keyword(.let),
      member.bindings.count == 1,
      let binding = member.bindings.first,
      binding.typeAnnotation == nil,
      binding.accessorBlock == nil
    else { return nil }
    return member
  }

  private func entries(
    in call: FunctionCallExprSyntax,
    named name: String
  ) -> Result<[Baseline.Entry], Diagnostic>? {
    let arguments = Array(call.arguments)
    guard arguments.count == 2 else { return nil }
    let entriesArgument = arguments[1]
    guard call.calledExpression.as(DeclReferenceExprSyntax.self)?
      .baseName.text == "Baseline",
      call.trailingClosure == nil,
      call.additionalTrailingClosures.isEmpty,
      let baselineName = string(arguments[0]),
      baselineName == name,
      entriesArgument.label?.text == "entries",
      let array = entriesArgument.expression.as(ArrayExprSyntax.self)
    else { return nil }

    var entries: [Baseline.Entry] = []
    for element in array.elements {
      guard let entry = entry(from: element.expression) else {
        return .failure(malformedEntry(at: element))
      }
      entries.append(entry)
    }
    return .success(entries)
  }

  private func string(_ argument: LabeledExprSyntax) -> String? {
    guard argument.label == nil,
          argument.colon == nil,
          let literal = argument.expression.as(StringLiteralExprSyntax.self)
    else { return nil }
    return literal.representedLiteralValue
  }

  private func entry(from expression: ExprSyntax) -> Baseline.Entry? {
    guard let call = expression.as(FunctionCallExprSyntax.self),
          call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
          == "Entry",
          call.trailingClosure == nil,
          call.additionalTrailingClosures.isEmpty,
          call.arguments.count == 3
    else { return nil }

    let arguments = Array(call.arguments)
    guard let rule = string(arguments[0], labelled: "rule"),
          let declaration = string(arguments[1], labelled: "declaration"),
          let file = string(arguments[2], labelled: "file")
    else { return nil }
    return Baseline.Entry(
      rule: Rule.ID(rule),
      declaration: declaration,
      file: file
    )
  }

  private func string(
    _ argument: LabeledExprSyntax,
    labelled label: String
  ) -> String? {
    guard argument.label?.text == label,
          argument.colon != nil,
          let literal = argument.expression.as(StringLiteralExprSyntax.self)
    else { return nil }
    return literal.representedLiteralValue
  }

  private func syntaxError(in tree: SourceFileSyntax) -> Diagnostic {
    guard let parseError = ParseDiagnosticsGenerator.diagnostics(for: tree)
      .first
    else { return malformedFile(at: tree) }
    return error(parseError.message, at: parseError.node)
  }

  private func malformedFile(at node: some SyntaxProtocol) -> Diagnostic {
    error("the baseline file does not match the .record format", at: node)
  }

  private func malformedEntry(at node: some SyntaxProtocol) -> Diagnostic {
    error(
      "each Entry takes rule, declaration and file string literals",
      at: node
    )
  }

  private func location(of node: some SyntaxProtocol) -> DeclarationLocation {
    DeclarationLocation(of: node, converter: converter, filePath: path)
  }

  private func error(
    _ message: String,
    at node: some SyntaxProtocol
  ) -> Diagnostic {
    .error(message, at: location(of: node))
  }
}
