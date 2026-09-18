import BylawsSyntax

/// A conditional-compilation branch in the source file.
public struct CompilationBranch: Declaration {
  /// The condition as source text, or `nil` for `#else`.
  public let condition: String?

  /// The conditions of earlier branches in the same `#if` chain, in order.
  public let precedingConditions: [String]

  /// The start of the branch directive.
  public let location: DeclarationLocation

  private let bodyStart: DeclarationLocation
  private let bodyEnd: DeclarationLocation

  /// The directive and condition, such as `#if DEBUG`.
  public var name: String {
    guard let condition else { return "#else" }
    let directive = precedingConditions.isEmpty ? "#if" : "#elseif"
    return "\(directive) \(condition)"
  }

  /// Returns whether the position is inside this branch's body.
  ///
  /// The body starts after the directive and its condition.
  public func contains(_ position: DeclarationLocation) -> Bool {
    position.filePath == location.filePath
      && (position.line, position.column) >= (bodyStart.line, bodyStart.column)
      && (position.line, position.column) < (bodyEnd.line, bodyEnd.column)
  }

  init(_ clause: IfConfigClauseSyntax, context: SourceContext) {
    condition = clause.condition.map(context.source.trimmedText)
    precedingConditions = clause.parent?.as(IfConfigClauseListSyntax.self)?
      .prefix(while: { $0.id != clause.id })
      .compactMap { $0.condition.map(context.source.trimmedText) } ?? []
    location = context
      .location(at: clause.poundKeyword.positionAfterSkippingLeadingTrivia)
    let start = clause.elements?.positionAfterSkippingLeadingTrivia ?? clause
      .endPosition
    let end = clause.elements?.endPositionBeforeTrailingTrivia ?? start
    bodyStart = context.location(at: start)
    bodyEnd = context.location(at: end)
  }
}
