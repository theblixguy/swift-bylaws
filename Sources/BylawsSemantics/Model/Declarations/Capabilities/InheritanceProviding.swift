/// A declaration with an inheritance clause.
public protocol InheritanceProviding: Sendable {
  /// The type names in the declaration's own inheritance clause, as written.
  var inheritedTypes: [String] { get }

  /// Type names added through extensions elsewhere in the codebase.
  var extensionInheritedTypes: [String] { get }

  /// Every type name the declaration inherits or conforms to, including
  /// names reached through intermediate types and typealiases declared
  /// in the codebase.
  var allInheritedTypes: [String] { get }
}

extension InheritanceProviding {
  /// Checks whether the declaration inherits from `typeName`, directly or
  /// through intermediate types declared in the codebase.
  ///
  /// Resolution follows declared typealiases through types in the codebase.
  public func inherits(from typeName: String) -> Bool {
    allInheritedTypes.contains(typeName)
  }

  /// Checks the declaration's own inheritance clause for `typeName`, ignoring
  /// attributes such as `@unchecked` and `@MainActor`.
  public func directlyInherits(from typeName: String) -> Bool {
    inheritedTypes.contains {
      $0 == typeName || $0.withoutTypeAttributes == typeName
    }
  }

  /// Checks for a conformance to `typeName`.
  ///
  /// Direct and extension-added conformances appear in the result. Inheritance
  /// traversal resolves declared typealiases through types in the codebase and
  /// stops at external types. Syntax-level analysis merges same-named top-level
  /// types from different modules. Extensions of either type then reach both.
  public func conforms(to typeName: String) -> Bool {
    allInheritedTypes.contains(typeName)
  }

  /// Checks for a direct conformance to `typeName`.
  ///
  /// The declaration's own inheritance clause or any extension may name the
  /// type. Attributes such as `@unchecked` are ignored.
  public func directlyConforms(to typeName: String) -> Bool {
    (inheritedTypes + extensionInheritedTypes).contains {
      $0 == typeName || $0.withoutTypeAttributes == typeName
    }
  }
}

extension String {
  package var withoutTypeAttributes: String {
    var entry = Substring(self)
    while entry.hasPrefix("@") {
      guard let space = entry.firstIndex(of: " ") else { return self }
      entry = entry[entry.index(after: space)...].drop { $0 == " " }
    }
    return String(entry)
  }
}
