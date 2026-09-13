/// The data a class, struct, enum or actor declaration records.
///
/// Read this data through the declaration's own properties.
public struct NominalTypeStorage: Sendable {
  /// The declared name, without enclosing types.
  public let name: String

  /// The type names written in the declaration's inheritance clause.
  public let inheritedTypes: [String]

  /// The parameters of the type's generic clause, in order.
  public let genericParameters: [GenericParameter]

  package let source: SourceBuffer

  /// The UTF-8 byte range of the declaration's source text in the file.
  public let sourceRange: Range<Int>

  /// Whether the declaration is marked `nonisolated`.
  public let isNonisolated: Bool

  /// The access level written on the declaration.
  public let visibility: Visibility

  /// The attributes, such as `@MainActor`.
  public let attributes: [Attribute]

  /// The dot-joined name of the enclosing types, or `nil` at file scope.
  public let enclosingTypeName: String?

  /// The documentation comment, or `nil` when the declaration has none.
  public let documentation: String?

  /// The position of the declared name in the file.
  public let location: DeclarationLocation

  /// The conformances that extensions add to the type.
  public package(set) var extensionInheritedTypes: [String] = []

  /// Every inherited type, direct and transitive, including the ones
  /// extensions add.
  public package(set) var allInheritedTypes: [String]

  package var memberStorage = MemberStorage.empty

  package init(
    name: String,
    inheritedTypes: [String],
    genericParameters: [GenericParameter] = [],
    source: SourceBuffer,
    sourceRange: Range<Int> = 0..<0,
    isNonisolated: Bool = false,
    visibility: Visibility,
    attributes: [Attribute] = [],
    enclosingTypeName: String? = nil,
    documentation: String? = nil,
    location: DeclarationLocation
  ) {
    self.name = name
    self.inheritedTypes = inheritedTypes
    self.genericParameters = genericParameters
    self.source = source
    self.sourceRange = sourceRange
    self.isNonisolated = isNonisolated
    self.visibility = visibility
    self.attributes = attributes
    self.enclosingTypeName = enclosingTypeName
    self.documentation = documentation
    self.location = location
    allInheritedTypes = inheritedTypes
  }
}

extension NominalTypeStorage: SourceTextProviding {}

/// A class, struct, enum or actor declaration.
public protocol NominalTypeDeclaration: TypeDeclaration, Documented {
  /// The data the declaration shares with the other nominal kinds.
  var storage: NominalTypeStorage { get }
}

extension NominalTypeDeclaration {
  public var name: String { storage.name }
  public var inheritedTypes: [String] { storage.inheritedTypes }
  public var genericParameters: [GenericParameter] {
    storage.genericParameters
  }

  public var sourceRange: Range<Int> { storage.sourceRange }
  public var isNonisolated: Bool { storage.isNonisolated }
  public var visibility: Visibility { storage.visibility }
  public var attributes: [Attribute] { storage.attributes }
  public var enclosingTypeName: String? { storage.enclosingTypeName }
  public var documentation: String? { storage.documentation }
  public var location: DeclarationLocation { storage.location }
  public var extensionInheritedTypes: [String] {
    storage.extensionInheritedTypes
  }

  public var allInheritedTypes: [String] { storage.allInheritedTypes }

  /// The declaration's source text, as written.
  ///
  /// Prefer model properties. Inspect the text only for checks they cannot
  /// express.
  ///
  /// - Complexity: O(n), where n is the number of UTF-8 bytes in the text.
  public var sourceText: String { storage.sourceText }

  /// The stored and computed properties declared directly in this type.
  public var properties: MemberCollection<Property> {
    storage.memberStorage.properties(of: qualifiedName)
  }

  /// The functions declared directly in this type.
  public var functions: MemberCollection<Function> {
    storage.memberStorage.functions(of: qualifiedName)
  }

  /// The initialisers declared directly in this type.
  public var initializers: MemberCollection<Initializer> {
    storage.memberStorage.initializers(of: qualifiedName)
  }
}

package protocol NominalTypeStorageMutating: NominalTypeDeclaration {
  var storage: NominalTypeStorage { get set }
}

extension NominalTypeStorageMutating {
  package func sharing(_ memberStorage: MemberStorage) -> Self {
    var copy = self
    copy.storage.memberStorage = memberStorage
    return copy
  }

  package func resolvingInheritance(
    extensionInheritedTypes: [String],
    allInheritedTypes: ([String]) -> [String]
  ) -> Self {
    var copy = self
    copy.storage.extensionInheritedTypes = extensionInheritedTypes
    copy.storage.allInheritedTypes = allInheritedTypes(
      inheritedTypes + extensionInheritedTypes
    )
    return copy
  }
}
