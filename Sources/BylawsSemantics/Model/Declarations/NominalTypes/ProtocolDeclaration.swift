/// A `protocol` declaration, as written in one source file.
public struct ProtocolDeclaration: Declaration, Visible, Attributed,
  InheritanceProviding, Documented, SourceTextProviding
{
  public let name: String
  public let inheritedTypes: [String]
  package let source: SourceBuffer

  /// The UTF-8 byte range of `sourceText` in the file's text.
  public let sourceRange: Range<Int>

  /// Whether the declaration is marked `nonisolated`.
  public let isNonisolated: Bool
  public let visibility: Visibility
  public let attributes: [Attribute]
  public let documentation: String?
  public package(set) var location: DeclarationLocation

  public package(set) var extensionInheritedTypes: [String] = []
  public package(set) var allInheritedTypes: [String] = []

  /// The function requirements declared in the protocol's body.
  public package(set) var requiredFunctions: [Function]

  /// The property requirements declared in the protocol's body.
  public package(set) var requiredProperties: [Property]

  package init(
    name: String,
    inheritedTypes: [String],
    source: SourceBuffer,
    sourceRange: Range<Int> = 0..<0,
    isNonisolated: Bool = false,
    visibility: Visibility,
    attributes: [Attribute] = [],
    requiredFunctions: [Function] = [],
    requiredProperties: [Property] = [],
    documentation: String? = nil,
    location: DeclarationLocation
  ) {
    self.name = name
    self.inheritedTypes = inheritedTypes
    self.source = source
    self.sourceRange = sourceRange
    self.isNonisolated = isNonisolated
    allInheritedTypes = inheritedTypes
    self.visibility = visibility
    self.attributes = attributes
    self.requiredFunctions = requiredFunctions
    self.requiredProperties = requiredProperties
    self.documentation = documentation
    self.location = location
  }
}

extension ProtocolDeclaration: CustomStringConvertible {}
