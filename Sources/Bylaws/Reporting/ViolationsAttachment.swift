#if canImport(Testing)
  public import BylawsCore
  @_weakLinked public import Testing

  extension Violations {
    /// Attaches a markdown report of these violations to the current test.
    ///
    /// CI can collect attachments with `swift test --attachments-path`.
    /// A run with no violations attaches nothing.
    public func attachReport(
      named name: String = "violations.md",
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      guard !isEmpty else { return }
      Attachment.record(
        markdownReport,
        named: name,
        sourceLocation: sourceLocation
      )
    }

    /// The violations as a markdown document.
    public var markdownReport: String {
      let listing = offenders
        .map { "- \(String(describing: $0))" }
        .joined(separator: "\n")
      return """
      # Violations

      Rule: \(rule)
      Checked: \(checkedCount)
      Violations: \(count)

      \(listing)
      """
    }
  }
#endif
