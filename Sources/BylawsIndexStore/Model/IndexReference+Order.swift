extension IndexReference {
  static func areInStableOrder(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.file != rhs.file { return lhs.file < rhs.file }
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    if lhs.column != rhs.column { return lhs.column < rhs.column }
    if lhs.module != rhs.module { return lhs.module < rhs.module }
    if lhs.symbol.usr != rhs.symbol.usr {
      return lhs.symbol.usr < rhs.symbol.usr
    }
    if lhs.symbol.name != rhs.symbol.name {
      return lhs.symbol.name < rhs.symbol.name
    }
    let lhsKind = String(describing: lhs.symbol.kind)
    let rhsKind = String(describing: rhs.symbol.kind)
    if lhsKind != rhsKind { return lhsKind < rhsKind }
    return lhs.roles.rawValue < rhs.roles.rawValue
  }
}
