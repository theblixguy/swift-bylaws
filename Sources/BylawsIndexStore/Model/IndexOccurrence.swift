/// One place in the source where a symbol appears.
public struct IndexOccurrence: Sendable, Hashable {
  /// The symbol that appears here.
  public let symbol: IndexSymbol

  /// What the symbol does here.
  public let roles: SymbolRole

  /// The line, counted from 1.
  public let line: Int

  /// The column, counted from 1.
  public let column: Int

  /// The symbols this occurrence relates to, such as the type a
  /// conformance names.
  public let relations: [IndexRelation]

  /// Creates an occurrence of `symbol` at the given line and column.
  public init(
    symbol: IndexSymbol,
    roles: SymbolRole,
    line: Int,
    column: Int,
    relations: [IndexRelation] = []
  ) {
    self.symbol = symbol
    self.roles = roles
    self.line = line
    self.column = column
    self.relations = relations
  }

  /// Returns the relations that carry every role in `roles`.
  public func relations(having roles: SymbolRole) -> [IndexRelation] {
    relations.filter { $0.roles.contains(roles) }
  }
}
