/// An `init` declaration, as written in one source file.
public struct Initializer: Declaration, Visible, Attributed, Documented,
  Codable
{
  /// The initialiser's parameters, in order.
  public let parameters: [Parameter]

  /// Whether the initialiser is failable (`init?` or `init!`).
  public let isFailable: Bool

  /// Whether the initialiser is marked `convenience`.
  public let isConvenience: Bool

  /// Whether the initialiser is declared `async`.
  public let isAsync: Bool

  /// Whether the initialiser is declared `throws` or `rethrows`.
  public let isThrowing: Bool

  /// Whether the initialiser is marked `nonisolated`.
  public let isNonisolated: Bool

  public let visibility: Visibility
  public let attributes: [Attribute]

  /// The qualified name of the type that declares this initialiser.
  public let enclosingTypeName: String?

  /// The call expressions in the initialiser's body.
  public package(set) var calls: [FunctionCall]

  /// The number of `await` expressions in the initialiser's body.
  public let awaitCount: Int

  /// The initialiser body's cyclomatic complexity.
  ///
  /// The value starts at 0. Each `if`, `guard`, loop, `catch` and `switch`
  /// case adds 1. Each `fallthrough` subtracts 1.
  public let cyclomaticComplexity: Int

  public let documentation: String?
  public package(set) var location: DeclarationLocation

  /// Creates an initialiser model.
  public init(
    parameters: [Parameter],
    isFailable: Bool,
    isConvenience: Bool = false,
    isAsync: Bool = false,
    isThrowing: Bool = false,
    isNonisolated: Bool = false,
    visibility: Visibility,
    attributes: [Attribute] = [],
    enclosingTypeName: String? = nil,
    calls: [FunctionCall] = [],
    awaitCount: Int = 0,
    cyclomaticComplexity: Int = 0,
    documentation: String? = nil,
    location: DeclarationLocation
  ) {
    self.parameters = parameters
    self.isFailable = isFailable
    self.isConvenience = isConvenience
    self.isAsync = isAsync
    self.isThrowing = isThrowing
    self.isNonisolated = isNonisolated
    self.visibility = visibility
    self.attributes = attributes
    self.enclosingTypeName = enclosingTypeName
    self.calls = calls
    self.awaitCount = awaitCount
    self.cyclomaticComplexity = cyclomaticComplexity
    self.documentation = documentation
    self.location = location
  }

  /// The fixed initialiser name, `init`.
  public var name: String { "init" }
}

extension Initializer: CustomStringConvertible {
  /// The signature, formatted as `init(label:)`.
  public var summary: String {
    "init(\(parameters.map { "\($0.label ?? "_"):" }.joined()))"
  }
}
