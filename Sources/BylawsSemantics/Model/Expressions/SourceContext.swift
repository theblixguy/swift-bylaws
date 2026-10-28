import BylawsSyntax

struct SourceContext: Sendable {
  let source: SourceText
  let origin: DeclarationLocation
  let inheritedDeclarations: [EnclosingDeclaration]
  let inheritedBranches: [CompilationBranch]
  let propertiesByOffset: [Int: Property]

  init(
    source: SourceText, origin: DeclarationLocation,
    inheritedDeclarations: [EnclosingDeclaration] = [],
    inheritedBranches: [CompilationBranch] = [],
    propertiesByOffset: [Int: Property] = [:]
  ) {
    self.source = source
    self.origin = origin
    self.inheritedDeclarations = inheritedDeclarations
    self.inheritedBranches = inheritedBranches
    self.propertiesByOffset = propertiesByOffset
  }

  func sourceSlice(of node: some SyntaxProtocol) throws -> SourceSlice {
    let snapshot = try source.capturedBuffer.snapshot.required()
    guard snapshot.filePath == origin.filePath,
          let offset = origin.utf8Offset
    else { throw SourceError.unavailable }
    let range = source.trimmedRange(of: node)
    return try SourceSlice(
      snapshot: snapshot,
      range: (offset + range.lowerBound)..<(offset + range.upperBound)
    )
  }

  func parsedSource(of node: some SyntaxProtocol) -> ParsedSource? {
    guard source.capturedBuffer.sourcePath == origin.filePath,
          let offset = origin.utf8Offset
    else { return nil }
    let range = source.trimmedRange(of: node)
    return ParsedSource(
      buffer: source.capturedBuffer,
      range: (offset + range.lowerBound)..<(offset + range.upperBound)
    )
  }

  func location(at start: AbsolutePosition) -> DeclarationLocation {
    let relative = source.location(of: start)
    let column =
      if relative.line == 1 {
        origin.column + relative.column - 1
      } else {
        relative.column
      }
    return DeclarationLocation(
      filePath: origin.filePath,
      line: origin.line + relative.line - 1,
      column: column,
      utf8Offset: origin.utf8Offset.map { $0 + start.utf8Offset }
    )
  }

  func enclosingDeclarations(of syntax: some SyntaxProtocol)
    -> [EnclosingDeclaration]
  {
    var result: [EnclosingDeclaration] = []
    var parent = syntax.parent
    while let node = parent {
      if let name = declarationName(node) {
        result.append(
          EnclosingDeclaration(
            name: name,
            location: location(at: node.positionAfterSkippingLeadingTrivia)
          )
        )
      }
      parent = node.parent
    }
    return result + inheritedDeclarations
  }

  private func declarationName(_ node: Syntax) -> String? {
    switch node.as(SyntaxEnum.self) {
    case let .functionDecl(value): value.name.text
    case let .initializerDecl(value): value.initKeyword.text
    case let .deinitializerDecl(value): value.deinitKeyword.text
    case let .accessorDecl(value): value.accessorSpecifier.text
    case let .patternBinding(value): source.trimmedText(of: value.pattern)
    case let .optionalBindingCondition(value):
      source.trimmedText(of: value.pattern)
    case let .structDecl(value): value.name.text
    case let .classDecl(value): value.name.text
    case let .actorDecl(value): value.name.text
    case let .enumDecl(value): value.name.text
    case let .protocolDecl(value): value.name.text
    case let .extensionDecl(value): source.trimmedText(of: value.extendedType)
    case let .subscriptDecl(value): value.subscriptKeyword.text
    default: nil
    }
  }
}
