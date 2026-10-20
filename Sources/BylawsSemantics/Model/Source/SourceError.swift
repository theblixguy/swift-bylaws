/// An error when reading source for a correction.
public enum SourceError: Error, Sendable, Equatable, CustomStringConvertible {
  /// The model has no captured source.
  case unavailable

  /// The parsed model has no source for the requested part.
  case missingPart

  /// The slice does not match a syntax node of the requested type.
  case syntaxMismatch

  /// The range is outside its source or splits a UTF-8 sequence.
  case rangeOutOfBounds

  /// A source match query found a count other than one.
  case matchCount(Int)

  /// A description of the source error and how to resolve it.
  public var description: String {
    switch self {
    case .unavailable:
      "Source must come from a parsed file. Query a model from FileCollector."
    case .missingPart:
      "Source must contain the requested part. Select a model with that part."
    case .syntaxMismatch:
      "SourceSlice must match the requested syntax node. Select a slice with that type and range."
    case .rangeOutOfBounds:
      "Source range must fit the source and UTF-8 boundaries. Select a source slice."
    case let .matchCount(count):
      "Source matches must contain one match, found \(count). Refine the source query."
    }
  }
}
