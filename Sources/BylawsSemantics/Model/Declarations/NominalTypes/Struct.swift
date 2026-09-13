/// A `struct` declaration, as written in one source file.
public struct Struct: NominalTypeDeclaration, NominalTypeStorageMutating {
  /// The data the declaration shares with the other nominal kinds.
  public package(set) var storage: NominalTypeStorage

  package init(storage: NominalTypeStorage) {
    self.storage = storage
  }
}

extension Struct: CustomStringConvertible {}
