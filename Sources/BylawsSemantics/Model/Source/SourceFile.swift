import BylawsPaths

/// One parsed Swift source file and the declarations it contains.
///
/// A type declaration reads its members from the same source-ordered
/// collections exposed by the file. Each member records its enclosing type.
public struct SourceFile: Named, Located, Hashable {
  /// The absolute path of the file.
  public let path: String

  /// The language mode used to parse this file and its syntax queries.
  public let swiftLanguageMode: SwiftLanguageMode

  package let source: SourceBuffer

  /// The file's source text.
  public var sourceText: String { source.text }

  /// The import declarations in the file.
  public package(set) var imports: [Import]

  /// The classes declared outside function bodies, including nested classes.
  public package(set) var classes: [Class]

  /// The actors declared outside function bodies, including nested actors.
  public package(set) var actors: [Actor]

  /// The structs declared outside function bodies, including nested structs.
  public package(set) var structs: [Struct]

  /// The enums declared outside function bodies, including nested enums.
  public package(set) var enums: [Enum]

  /// The protocols declared in the file.
  public package(set) var protocols: [ProtocolDeclaration]

  /// The extensions declared in the file.
  public package(set) var extensions: [Extension]

  package let memberStorage: MemberStorage

  /// The free and member functions declared in the file.
  ///
  /// Local functions inside a function body are not included.
  public var functions: [Function] { memberStorage.functions }

  /// The global and member properties declared in the file.
  ///
  /// Local variables inside a function body are not included.
  public var properties: [Property] { memberStorage.properties }

  /// The initialisers declared in the file.
  public var initializers: [Initializer] { memberStorage.initializers }

  /// The typealiases declared in the file.
  public package(set) var typealiases: [Typealias]

  /// The declaration macros written in the file, such as `#Preview`. Their
  /// names retain the `#` prefix.
  public package(set) var macroExpansions: [FunctionCall]

  package init(
    path: String,
    source: SourceBuffer,
    swiftLanguageMode: SwiftLanguageMode = .v6,
    imports: [Import] = [],
    classes: [Class] = [],
    actors: [Actor] = [],
    structs: [Struct] = [],
    enums: [Enum] = [],
    protocols: [ProtocolDeclaration] = [],
    extensions: [Extension] = [],
    functions: [Function] = [],
    properties: [Property] = [],
    initializers: [Initializer] = [],
    typealiases: [Typealias] = [],
    macroExpansions: [FunctionCall] = []
  ) {
    self.path = path
    self.source = source
    self.swiftLanguageMode = swiftLanguageMode
    self.imports = imports
    let memberStorage = MemberStorage(
      functions: functions,
      properties: properties,
      initializers: initializers
    )
    self.memberStorage = memberStorage
    self.classes = classes.map { $0.sharing(memberStorage) }
    self.actors = actors.map { $0.sharing(memberStorage) }
    self.structs = structs.map { $0.sharing(memberStorage) }
    self.enums = enums.map { $0.sharing(memberStorage) }
    self.protocols = protocols
    self.extensions = extensions
    self.typealiases = typealiases
    self.macroExpansions = macroExpansions
  }

  /// The number of lines in the file.
  public var lineCount: Int { source.lineCount }

  /// The last path component of the file path.
  public var name: String {
    LexicalFilePath(path).lastComponent ?? path
  }

  /// The start of the file.
  public var location: DeclarationLocation {
    DeclarationLocation.start(of: path)
  }

  /// Whether the file imports `module`, directly or as a submodule path.
  ///
  /// Use the ``imports`` property for the import declarations themselves.
  public func imports(_ module: String) -> Bool {
    imports.contains { $0.references(module) }
  }

  /// The classes, structs, enums and actors declared outside function bodies,
  /// in source order, including nested types.
  ///
  /// - Complexity: O(n log n), where n is the number of types.
  public var types: [NominalType] {
    let types = classes.map(NominalType.class) + structs.map(NominalType.struct)
      + enums.map(NominalType.enum) + actors.map(NominalType.actor)
    return types
      .sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
  }

  /// The call expressions and declaration macros in the file.
  ///
  /// Calls include those in function and initialiser bodies, property
  /// initialiser values and property accessors.
  ///
  /// - Complexity: O(n), where n is the number of calls.
  public var calls: [FunctionCall] {
    functions.flatMap(\.calls) + initializers.flatMap(\.calls)
      + properties.flatMap(\.calls) + macroExpansions
  }

  /// Whether any call in the file references `identifier`.
  ///
  /// Use the ``calls`` property for the call declarations themselves.
  public func calls(_ identifier: String) -> Bool {
    firstCall { $0.references(identifier) } != nil
  }

  package func firstCall(where predicate: (FunctionCall) -> Bool)
    -> FunctionCall?
  {
    for function in functions {
      if let call = function.calls.first(where: predicate) { return call }
    }
    for initializer in initializers {
      if let call = initializer.calls.first(where: predicate) { return call }
    }
    for property in properties {
      if let call = property.calls.first(where: predicate) { return call }
    }
    return macroExpansions.first(where: predicate)
  }
}

extension SourceFile {
  /// Returns whether two files have the same path and source text.
  public static func == (lhs: SourceFile, rhs: SourceFile) -> Bool {
    lhs.path == rhs.path && lhs.sourceText == rhs.sourceText
  }

  /// Hashes the file's path and source text.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(path)
    hasher.combine(sourceText)
  }
}

extension SourceFile: Summarised, CustomStringConvertible {
  /// The file's name.
  public var summary: String { name }

  /// The file's name.
  public var description: String { name }
}
