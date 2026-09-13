/// A `class` declaration, as written in one source file.
public struct Class: NominalTypeDeclaration, NominalTypeStorageMutating {
  /// The data the declaration shares with the other nominal kinds.
  public package(set) var storage: NominalTypeStorage

  /// Whether the declaration is marked `final`.
  public let isFinal: Bool

  package init(storage: NominalTypeStorage, isFinal: Bool) {
    self.storage = storage
    self.isFinal = isFinal
  }
}

extension Class: CustomStringConvertible {}
