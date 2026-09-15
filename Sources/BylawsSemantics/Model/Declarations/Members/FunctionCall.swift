/// One call expression in a parsed source file.
public struct FunctionCall: Declaration, Codable {
  /// One argument of a call.
  public struct Argument: Sendable, Hashable, Codable {
    /// The argument's label, or `nil` when the argument has no label.
    public let label: String?

    /// The argument expression as source text, such as `"logo"` in
    /// `UIImage(named: "logo")`.
    public let text: String

    /// The argument's position in the source file, or `nil` if no position
    /// was supplied.
    public let location: DeclarationLocation?

    package let swiftLanguageMode: SwiftLanguageMode

    /// Creates an argument model.
    public init(
      label: String?, text: String,
      location: DeclarationLocation? = nil,
      swiftLanguageMode: SwiftLanguageMode = .v6
    ) {
      self.label = label
      self.text = text
      self.location = location
      self.swiftLanguageMode = swiftLanguageMode
    }

    /// The argument as a source expression.
    ///
    /// Returns `nil` when the argument has no source location or its text
    /// cannot be parsed as one expression.
    ///
    /// - Complexity: O(n), where n is the length of the argument text.
    public var expression: SourceExpression? {
      guard let location else { return nil }
      return SourceExpression.parse(
        text, at: location, swiftLanguageMode: swiftLanguageMode
      )
    }
  }

  /// The called expression as written, such as `save`,
  /// `UserDefaults.standard.set` or `Logger.init`.
  public let calledExpression: String

  /// The parenthesised arguments in source order.
  public let arguments: [Argument]

  public package(set) var location: DeclarationLocation

  /// Creates a function-call model.
  public init(
    calledExpression: String,
    arguments: [Argument] = [],
    location: DeclarationLocation
  ) {
    self.calledExpression = calledExpression
    self.arguments = arguments
    self.location = location
  }

  /// The argument labels in order, with `nil` for an unlabelled argument.
  public var argumentLabels: [String?] { arguments.map(\.label) }

  /// Checks whether any argument uses the label `label`, such as `named`
  /// in `UIImage(named: "logo")`.
  public func hasArgumentLabel(_ label: String) -> Bool {
    argumentLabels.contains(label)
  }

  /// The called expression.
  public var name: String { calledExpression }

  /// The first identifier of the called expression: `UserDefaults` for
  /// `UserDefaults.standard.set`.
  public var baseName: String {
    pathComponents.first ?? calledExpression
  }

  /// The last identifier of the called expression: `set` for
  /// `UserDefaults.standard.set`.
  public var memberName: String {
    pathComponents.last ?? calledExpression
  }

  /// Checks whether the call matches `identifier`.
  ///
  /// A single identifier matches any part of the called expression, while a
  /// dotted path requires neighbouring parts. For example, `standard` matches
  /// `UserDefaults.standard.set`, and `Task.detached` matches itself but not
  /// `Task.sleep`.
  ///
  /// When `identifier` includes argument labels, the call must have matching
  /// labels. Use `_` for an unlabelled argument and `()` for an empty argument
  /// list. Only arguments inside parentheses take part in this comparison,
  /// so `Task.detached()` matches `Task.detached { }`.
  public func references(_ identifier: String) -> Bool {
    let (path, labels) = FunctionCall.parts(of: identifier)
    guard referencesPath(path) else { return false }
    guard let labels else { return true }
    return argumentLabels.map { $0 ?? "_" } == labels
  }

  private func referencesPath(_ path: String) -> Bool {
    let parts = pathComponents
    let wanted = FunctionCall.pathComponents(of: path)
    guard wanted.count > 1 else { return parts.contains(path) }
    guard parts.count >= wanted.count else { return false }
    return (0...(parts.count - wanted.count)).contains { start in
      Array(parts[start..<(start + wanted.count)]) == wanted
    }
  }

  private var pathComponents: [String] {
    FunctionCall.pathComponents(of: calledExpression)
  }

  private static func pathComponents(of expression: String) -> [String] {
    expression.split(separator: ".").map { component in
      var component = component
      while component.last == "?" || component.last == "!" {
        component.removeLast()
      }
      return String(component)
    }
  }

  private static func parts(
    of identifier: String
  ) -> (path: String, labels: [String]?) {
    guard identifier.hasSuffix(")"),
          let open = identifier.firstIndex(of: "(")
    else { return (identifier, nil) }
    let inside = identifier[identifier.index(after: open)...].dropLast()
    let labels = inside.split(separator: ":", omittingEmptySubsequences: false)
      .dropLast()
      .map(String.init)
    return (String(identifier[..<open]), labels)
  }
}

extension FunctionCall: CustomStringConvertible {
  /// The called expression, as written.
  public var summary: String { calledExpression }
}
