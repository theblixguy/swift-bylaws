/// A Swift declaration extracted from parsed source.
///
/// Declarations of one concrete type compare equal when their names and
/// source positions match. Their source identity remains stable when
/// derived model data changes.
public protocol Declaration: Named, Located, Hashable, Summarised {}

extension Declaration {
  /// Returns whether two declarations have the same source identity.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name
      && lhs.location == rhs.location
  }

  /// Hashes the declaration's name and source position.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(location)
  }
}

extension Declaration {
  /// The declaration's name.
  public var summary: String { name }
}

extension Declaration where Self: CustomStringConvertible {
  /// The summary and location, formatted as `Name (File.swift:line)`.
  public var description: String {
    "\(summary) (\(location.fileName):\(location.line))"
  }
}
