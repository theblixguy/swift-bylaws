/// A symbol that one occurrence relates to and how it relates.
///
/// Protocol conformance appears as an occurrence of the protocol with a
/// ``SymbolRole/baseOf`` relation back to the conforming type.
public struct IndexRelation: Sendable, Hashable {
  /// The symbol at the other end of the relation.
  public let symbol: IndexSymbol

  /// The roles that `symbol` has relative to the occurrence.
  public let roles: SymbolRole

  /// Creates a relation from an occurrence to `symbol`.
  public init(symbol: IndexSymbol, roles: SymbolRole) {
    self.symbol = symbol
    self.roles = roles
  }
}
