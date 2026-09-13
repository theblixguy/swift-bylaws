#if canImport(Testing)
  @_weakLinked import Testing

  extension Issue {
    static func recordWarning(
      _ comment: Comment,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      #if compiler(>=6.3)
        Issue.record(
          comment,
          severity: .warning,
          sourceLocation: sourceLocation
        )
      #else
        withKnownIssue(isIntermittent: true, sourceLocation: sourceLocation) {
          Issue.record(comment, sourceLocation: sourceLocation)
        }
      #endif
    }
  }
#endif
