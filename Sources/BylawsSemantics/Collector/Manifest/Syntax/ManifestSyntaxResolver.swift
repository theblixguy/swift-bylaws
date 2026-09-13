import SwiftParser
import SwiftSyntax

struct ManifestSyntaxResolver {
  struct Expressions {
    var known: [ExprSyntax] = []
    var unresolved: [ExprSyntax] = []

    mutating func append(_ other: Self) {
      known.append(contentsOf: other.known)
      unresolved.append(contentsOf: other.unresolved)
    }
  }

  private let bindings: [String: ExprSyntax]
  private let sourceText: SourceText

  init(tree: SourceFileSyntax, source: String) {
    sourceText = SourceText(source: source)
    var values: [String: ExprSyntax] = [:]
    var duplicates = Set<String>()
    for statement in tree.statements {
      guard let declaration = statement.item.as(VariableDeclSyntax.self),
            declaration.bindingSpecifier.text == "let"
      else { continue }
      for binding in declaration.bindings {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?
          .identifier.text,
          let value = binding.initializer?.value
        else { continue }
        if values.updateValue(value, forKey: name) != nil {
          duplicates.insert(name)
        }
      }
    }
    bindings = values.filter { !duplicates.contains($0.key) }
  }

  func array(
    from expression: ExprSyntax,
    resolving names: Set<String> = []
  ) -> Expressions {
    if let array = expression.as(ArrayExprSyntax.self) {
      return Expressions(known: array.elements.map(\.expression))
    }
    if let reference = referenceName(in: expression),
       !names.contains(reference),
       let value = bindings[reference]
    {
      return array(from: value, resolving: names.union([reference]))
    }
    if let operands = additionOperands(in: expression) {
      var result = Expressions()
      for operand in operands {
        result.append(array(from: operand, resolving: names))
      }
      return result
    }
    if let call = expression.as(FunctionCallExprSyntax.self),
       call.isManifestSetInitializer,
       let contents = call.manifestUnlabelledArgument()
    {
      return array(from: contents, resolving: names)
    }
    return Expressions(unresolved: [expression])
  }

  func call(
    from expression: ExprSyntax,
    resolving names: Set<String> = []
  ) -> FunctionCallExprSyntax? {
    resolvedExpression(from: expression, resolving: names)?
      .as(FunctionCallExprSyntax.self)
  }

  func resolvedExpression(
    from expression: ExprSyntax,
    resolving names: Set<String> = []
  ) -> ExprSyntax? {
    guard referenceName(in: expression) != nil else { return expression }
    return resolvedReference(
      in: expression,
      resolving: names,
      using: resolvedExpression
    )
  }

  func string(
    from expression: ExprSyntax?,
    resolving names: Set<String> = []
  ) -> String? {
    guard let expression else { return nil }
    if let literal = expression.as(StringLiteralExprSyntax.self) {
      return literal.representedLiteralValue
    }
    if let value = resolvedReference(
      in: expression,
      resolving: names,
      using: string
    ) {
      return value
    }
    guard let operands = additionOperands(in: expression) else { return nil }
    let parts = operands.map { string(from: $0, resolving: names) }
    guard parts.allSatisfy({ $0 != nil }) else { return nil }
    return parts.compactMap(\.self).joined()
  }

  func bool(
    from expression: ExprSyntax?,
    resolving names: Set<String> = []
  ) -> Bool? {
    guard let expression else { return nil }
    if let literal = expression.as(BooleanLiteralExprSyntax.self) {
      return literal.literal.text == "true"
    }
    if let value = resolvedReference(
      in: expression,
      resolving: names,
      using: bool
    ) {
      return value
    }
    return nil
  }

  func integer(
    from expression: ExprSyntax?,
    resolving names: Set<String> = []
  ) -> Int? {
    guard let expression else { return nil }
    if let literal = expression.as(IntegerLiteralExprSyntax.self) {
      return Int(literal.literal.text)
    }
    if let value = resolvedReference(
      in: expression,
      resolving: names,
      using: integer
    ) {
      return value
    }
    return nil
  }

  func memberName(
    from expression: ExprSyntax?,
    resolving names: Set<String> = []
  ) -> String? {
    guard let expression else { return nil }
    if let member = expression.as(MemberAccessExprSyntax.self) {
      if let base = member.base {
        guard let typeName = base.manifestAccessPath?.last,
              ManifestEnumType(rawValue: typeName) != nil
        else {
          return nil
        }
      }
      return member.declName.baseName.text
    }
    if let value = resolvedReference(
      in: expression,
      resolving: names,
      using: memberName
    ) {
      return value
    }
    return nil
  }

  func strings(from expression: ExprSyntax?) -> ManifestList<String> {
    guard let expression else { return .init() }
    let expressions = array(from: expression)
    var values: [String] = []
    var unresolved = expressions.unresolved.map {
      issue(field: "", expression: $0)
    }
    for element in expressions.known {
      if let value = string(from: element) {
        values.append(value)
      } else {
        unresolved.append(issue(field: "", expression: element))
      }
    }
    return ManifestList(knownValues: values, unresolvedValues: unresolved)
  }

  func stringDictionary(from expression: ExprSyntax?) -> [String: String]? {
    stringDictionary(from: expression, resolving: [])
  }

  private func stringDictionary(
    from expression: ExprSyntax?,
    resolving names: Set<String>
  ) -> [String: String]? {
    guard let expression else { return [:] }
    if let reference = referenceName(in: expression),
       !names.contains(reference),
       let value = bindings[reference]
    {
      return stringDictionary(
        from: value,
        resolving: names.union([reference])
      )
    }
    guard let dictionary = expression.as(DictionaryExprSyntax.self),
          case let .elements(elements) = dictionary.content
    else { return nil }
    var result: [String: String] = [:]
    for element in elements {
      guard let key = string(from: element.key),
            let value = string(from: element.value)
      else { return nil }
      result[key] = value
    }
    return result
  }

  func issue(
    field: String,
    expression: some SyntaxProtocol
  ) -> PackageManifest.UnresolvedValue {
    let location = sourceText.location(
      of: expression.positionAfterSkippingLeadingTrivia
    )
    return PackageManifest.UnresolvedValue(
      field: field,
      expression: expression.trimmedDescription,
      line: location.line,
      column: location.column
    )
  }

  private func referenceName(in expression: ExprSyntax) -> String? {
    expression.as(DeclReferenceExprSyntax.self)?.baseName.text
  }

  private func resolvedReference<Value>(
    in expression: ExprSyntax,
    resolving names: Set<String>,
    using resolve: (ExprSyntax, Set<String>) -> Value?
  ) -> Value? {
    guard let reference = referenceName(in: expression),
          !names.contains(reference),
          let value = bindings[reference]
    else { return nil }
    return resolve(value, names.union([reference]))
  }

  private func additionOperands(in expression: ExprSyntax) -> [ExprSyntax]? {
    guard let operands = ManifestBinaryOperation(expression)?
      .operands(forOperator: ["+"])
    else { return nil }
    return [operands.left, operands.right]
  }
}

extension ManifestList {
  func assigningField(_ field: String) -> Self {
    Self(
      knownValues: knownValues,
      conditionalValues: conditionalValues,
      unresolvedValues: unresolvedValues.map {
        PackageManifest.UnresolvedValue(
          field: field,
          expression: $0.expression,
          line: $0.line,
          column: $0.column
        )
      }
    )
  }
}

extension FunctionCallExprSyntax {
  func manifestArgument(labelled label: String) -> ExprSyntax? {
    arguments.first { $0.label?.text == label }?.expression
  }

  func manifestUnlabelledArgument(at index: Int = 0) -> ExprSyntax? {
    let arguments = Array(arguments.filter { $0.label == nil })
    guard arguments.indices.contains(index) else { return nil }
    return arguments[index].expression
  }
}
