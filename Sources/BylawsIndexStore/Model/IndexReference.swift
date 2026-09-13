import BylawsPaths

/// Where a symbol appears and what it does there.
public struct IndexReference: Sendable, Hashable {
  /// The symbol at this place.
  public let symbol: IndexSymbol

  /// The module of the compiled file.
  public let module: String

  /// The path of the file.
  public let file: String

  /// The line, counted from 1.
  public let line: Int

  /// The column, counted from 1.
  public let column: Int

  /// What the symbol does here.
  public let roles: SymbolRole

  /// Creates a reference to `symbol` at the given source position.
  public init(
    symbol: IndexSymbol,
    module: String,
    file: String,
    line: Int,
    column: Int,
    roles: SymbolRole
  ) {
    self.symbol = symbol
    self.module = module
    self.file = file
    self.line = line
    self.column = column
    self.roles = roles
  }
}

extension IndexReference: CustomStringConvertible {
  /// The symbol and location as `name (File.swift:line)`.
  public var description: String {
    let name = LexicalFilePath(file).lastComponent ?? file
    return "\(symbol.name) (\(name):\(line):\(column))"
  }
}
