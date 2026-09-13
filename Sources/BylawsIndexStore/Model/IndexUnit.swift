/// One compiled file, as the index store records it.
public struct IndexUnit: Sendable, Hashable {
  /// The store's identifier for the unit.
  public let name: String

  /// The module of the compiled file.
  public let moduleName: String

  /// The path of the source file this unit covers.
  public let mainFile: String

  /// The records that hold this unit's symbol occurrences.
  public let records: [IndexRecord]

  /// An opaque compiler identity for this unit.
  ///
  /// Each build configuration of one source file has a different value,
  /// which can look like a path but might name no file.
  public let outputFile: String

  /// The store identifiers of the records this unit uses.
  ///
  /// Access takes O(n) time, where n is the number of records. Use ``records``
  /// when you also need each record's source path.
  public var recordNames: [String] { records.map(\.name) }

  /// Creates a unit with the given output identity.
  public init(
    name: String,
    moduleName: String,
    mainFile: String,
    records: [IndexRecord],
    outputFile: String
  ) {
    self.name = name
    self.moduleName = moduleName
    self.mainFile = mainFile
    self.records = records
    self.outputFile = outputFile
  }

  /// Creates a unit whose records belong to its main file and sets its output
  /// identity.
  ///
  /// Use ``init(name:moduleName:mainFile:records:outputFile:)`` when records
  /// can belong to other files, such as headers in a C or Objective-C unit.
  public init(
    name: String,
    moduleName: String,
    mainFile: String,
    recordNames: [String],
    outputFile: String
  ) {
    self.init(
      name: name,
      moduleName: moduleName,
      mainFile: mainFile,
      records: recordNames.map { IndexRecord(name: $0, file: mainFile) },
      outputFile: outputFile
    )
  }
}
