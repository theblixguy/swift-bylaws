/// An `enum` declaration, as written in one source file.
public struct Enum: NominalTypeDeclaration, NominalTypeStorageMutating {
  /// The data the declaration shares with the other nominal kinds.
  public package(set) var storage: NominalTypeStorage

  /// Whether the enum is marked `indirect`.
  public let isIndirect: Bool

  /// The cases declared in the enum.
  public package(set) var cases: [EnumCase] = []

  package init(storage: NominalTypeStorage, isIndirect: Bool = false) {
    self.storage = storage
    self.isIndirect = isIndirect
  }
}

extension Enum: CustomStringConvertible {}
