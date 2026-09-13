#if canImport(Testing)
  import BylawsPaths
  public import BylawsSemantics
  @_weakLinked public import Testing

  extension Located {
    /// The location of this declaration, as a Swift Testing source location.
    ///
    /// Pass it to `#expect(_:_:sourceLocation:)` to report a failure at the
    /// violating declaration instead of the test.
    public var testingLocation: SourceLocation {
      // Swift Testing expects file IDs in the form "Module/File".
      let parent = LexicalFilePath(location.filePath)
        .removingLastComponent()
        .lastComponent ?? "Sources"
      return SourceLocation(
        fileID: "\(parent)/\(location.fileName)",
        filePath: location.filePath,
        line: max(1, location.line),
        column: max(1, location.column)
      )
    }
  }
#endif
