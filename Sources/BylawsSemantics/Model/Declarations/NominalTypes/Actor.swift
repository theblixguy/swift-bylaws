/// An `actor` declaration, as written in one source file.
public struct Actor: NominalTypeDeclaration, NominalTypeStorageMutating {
  /// The data recorded for this declaration.
  public package(set) var storage: NominalTypeStorage

  package init(storage: NominalTypeStorage) {
    self.storage = storage
  }
}

extension Actor: CustomStringConvertible {}
