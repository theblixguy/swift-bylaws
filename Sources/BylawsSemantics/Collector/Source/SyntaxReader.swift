import SwiftSyntax

struct SyntaxReader {
  let path: String
  let text: SourceText

  func genericParameters(
    of clause: GenericParameterClauseSyntax?
  ) -> [GenericParameter] {
    clause?.parameters.map { parameter in
      GenericParameter(
        name: parameter.name.text,
        constraintName: parameter.inheritedType?.trimmedDescription
      )
    } ?? []
  }

  func location(of node: some SyntaxProtocol) -> DeclarationLocation {
    let start = node.positionAfterSkippingLeadingTrivia
    let position = text.location(of: start)
    return DeclarationLocation(
      filePath: path,
      line: position.line,
      column: position.column,
      utf8Offset: start.utf8Offset
    )
  }

  func inheritedTypeNames(_ clause: InheritanceClauseSyntax?)
    -> [String]
  {
    clause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
  }

  func documentation(of node: some SyntaxProtocol) -> String? {
    let lines = node.leadingTrivia.compactMap { piece -> String? in
      switch piece {
      case let .docLineComment(text): text
      case let .docBlockComment(text): text
      default: nil
      }
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  func lineCount(of body: CodeBlockSyntax?) -> Int {
    guard let body else { return 0 }
    let start = text
      .location(of: body.leftBrace.positionAfterSkippingLeadingTrivia).line
    let end = text
      .location(of: body.rightBrace.positionAfterSkippingLeadingTrivia).line
    return end - start + 1
  }

  func calls(in body: CodeBlockSyntax?) -> [FunctionCall] {
    guard let body else { return [] }
    let collector = CallCollector(path: path, text: text)
    collector.walk(body)
    return collector.calls
  }

  func calls(in accessors: AccessorBlockSyntax?) -> [FunctionCall] {
    guard let accessors else { return [] }
    let collector = CallCollector(
      path: path,
      text: text,
      visitsTopLevelAccessors: true
    )
    collector.walk(accessors)
    return collector.calls
  }

  func calls(in expression: ExprSyntax?) -> [FunctionCall] {
    guard let expression else { return [] }
    let collector = CallCollector(path: path, text: text)
    collector.walk(expression)
    return collector.calls
  }

  func bodyMetrics(of body: CodeBlockSyntax?)
    -> (awaitCount: Int, cyclomaticComplexity: Int)
  {
    guard let body else { return (0, 0) }
    let collector = BodyMetricsCollector()
    collector.walk(body)
    return (collector.awaitCount, collector.cyclomaticComplexity)
  }

  func parameters(of clause: FunctionParameterClauseSyntax)
    -> [Parameter]
  {
    clause.parameters.map { parameter in
      Parameter(
        label: parameter.firstName.tokenKind == .wildcard ? nil : parameter
          .firstName.text,
        name: (parameter.secondName ?? parameter.firstName).text,
        type: TypeReference(parameter.type)
      )
    }
  }

  func trimmedRange(of node: some SyntaxProtocol) -> Range<Int> {
    text.trimmedRange(of: node)
  }

  func trimmedSourceText(of node: some SyntaxProtocol) -> String {
    text.trimmedText(of: node)
  }
}
