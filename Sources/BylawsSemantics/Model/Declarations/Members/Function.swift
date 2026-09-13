/// A `func` declaration, as written in one source file.
public struct Function: Declaration, Visible, Attributed, Documented,
  SourceTextProviding
{
  public let name: String
  package let source: SourceBuffer

  /// The function's parameters, in order.
  public let parameters: [Parameter]

  /// The return type as written, or `nil` when no return clause appears.
  ///
  /// Explicit `Void` and `()` return types are preserved.
  public let returnType: TypeReference?

  /// The return type text, or `nil` when no return clause appears.
  public var returnTypeName: String? { returnType?.text }

  /// Whether the function is `static` or `class`-scoped.
  public let isStatic: Bool

  /// Whether the function is marked `override`.
  public let isOverride: Bool

  /// Whether the function is marked `mutating`.
  public let isMutating: Bool

  /// Whether the function is marked `dynamic`.
  public let isDynamic: Bool

  /// Whether the function is declared `async`.
  public let isAsync: Bool

  /// Whether the function is declared `throws` or `rethrows`.
  public let isThrowing: Bool

  /// Whether the function is marked `nonisolated`.
  public let isNonisolated: Bool

  /// The parameters of the function's generic clause, in order.
  public let genericParameters: [GenericParameter]

  public let visibility: Visibility
  public let attributes: [Attribute]

  /// The qualified name of the type that declares this function, or `nil`
  /// for free functions.
  public let enclosingTypeName: String?

  /// The call expressions in the function's body.
  public package(set) var calls: [FunctionCall]

  /// The number of lines in the function's body, or 0 when there is none.
  public let bodyLineCount: Int

  /// The number of `await` expressions in the function's body.
  public let awaitCount: Int

  /// The function body's cyclomatic complexity.
  ///
  /// The value starts at 0. Each `if`, `guard`, loop, `catch` and `switch`
  /// case adds 1. Each `fallthrough` subtracts 1.
  public let cyclomaticComplexity: Int

  /// The UTF-8 byte range of `sourceText` in the file's text.
  public let sourceRange: Range<Int>

  public let documentation: String?
  public package(set) var location: DeclarationLocation

  package init(
    name: String,
    source: SourceBuffer,
    parameters: [Parameter],
    returnType: TypeReference?,
    isStatic: Bool,
    isOverride: Bool = false,
    isMutating: Bool = false,
    isDynamic: Bool = false,
    isAsync: Bool = false,
    isThrowing: Bool = false,
    isNonisolated: Bool = false,
    genericParameters: [GenericParameter] = [],
    visibility: Visibility,
    attributes: [Attribute] = [],
    enclosingTypeName: String? = nil,
    calls: [FunctionCall] = [],
    bodyLineCount: Int = 0,
    awaitCount: Int = 0,
    cyclomaticComplexity: Int = 0,
    sourceRange: Range<Int> = 0..<0,
    documentation: String? = nil,
    location: DeclarationLocation
  ) {
    self.name = name
    self.source = source
    self.parameters = parameters
    self.returnType = returnType
    self.isStatic = isStatic
    self.isOverride = isOverride
    self.isMutating = isMutating
    self.isDynamic = isDynamic
    self.isAsync = isAsync
    self.isThrowing = isThrowing
    self.isNonisolated = isNonisolated
    self.genericParameters = genericParameters
    self.visibility = visibility
    self.attributes = attributes
    self.enclosingTypeName = enclosingTypeName
    self.calls = calls
    self.bodyLineCount = bodyLineCount
    self.awaitCount = awaitCount
    self.cyclomaticComplexity = cyclomaticComplexity
    self.sourceRange = sourceRange
    self.documentation = documentation
    self.location = location
  }

  /// Whether any call in the body references `identifier`, such as
  /// `UserDefaults` in `UserDefaults.standard.set(true, forKey: "seen")`.
  ///
  /// Use the ``calls`` property for the call declarations themselves.
  public func calls(_ identifier: String) -> Bool {
    calls.contains { $0.references(identifier) }
  }
}

extension Function: CustomStringConvertible {
  /// The signature, formatted as `name(label:)`.
  public var summary: String {
    "\(name)(\(parameters.map { "\($0.label ?? "_"):" }.joined()))"
  }
}
