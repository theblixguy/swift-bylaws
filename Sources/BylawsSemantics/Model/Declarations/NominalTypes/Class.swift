/// A `class` declaration, as written in one source file.
public struct Class: NominalTypeDeclaration, NominalTypeStorageMutating {
  /// The data recorded for this declaration.
  public package(set) var storage: NominalTypeStorage

  /// Whether the declaration is marked `final`.
  public let isFinal: Bool

  package init(storage: NominalTypeStorage, isFinal: Bool) {
    self.storage = storage
    self.isFinal = isFinal
  }
}

extension Class: CustomStringConvertible {}
