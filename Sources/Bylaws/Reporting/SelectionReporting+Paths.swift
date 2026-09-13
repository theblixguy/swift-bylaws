#if canImport(Testing)
  public import BylawsCore
  public import BylawsSemantics
  @_weakLinked public import Testing

  extension Selection where Element: Located {
    /// Returns violations for files or declarations outside the permitted path.
    ///
    /// The glob matches paths relative to the codebase root.
    /// Use a trailing `/**` to include every file below a folder.
    public func violations(
      outsidePaths pattern: String,
      sourceLocation: SourceLocation = #_sourceLocation
    ) -> Violations<Element> {
      violations(outsidePaths: [pattern], sourceLocation: sourceLocation)
    }

    /// Returns violations for files or declarations outside all permitted paths.
    ///
    /// The globs match paths relative to the codebase root.
    /// An empty selection records a non-failing test issue.
    public func violations(
      outsidePaths patterns: [String],
      sourceLocation: SourceLocation = #_sourceLocation
    ) -> Violations<Element> {
      violations(of: pathRequirement(patterns), sourceLocation: sourceLocation)
    }
  }
#endif
