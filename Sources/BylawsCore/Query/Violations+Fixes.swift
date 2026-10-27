public import BylawsSemantics

/// An offender and the captured source available to its correction.
public struct FixContext<Element: Sendable>: Sendable {
  /// The element that failed the check.
  public let offender: Element

  private let queryCodebase: Codebase?

  package init(offender: Element, codebase: Codebase? = nil) {
    self.offender = offender
    queryCodebase = codebase
  }

  /// The offender's original source.
  ///
  /// A declaration's source excludes outer trivia. A
  /// ``/BylawsSemantics/SourceFile`` provides the complete file, including its
  /// trivia. A reporting location alone cannot provide an editable source range.
  ///
  /// - Throws: ``FixContextError/sourceUnavailable`` when the offender does
  ///   not conform to ``/BylawsSemantics/SourceProviding``. Errors from its
  ///   source provider pass through unchanged.
  public var source: SourceSlice {
    get throws {
      guard let provider = offender as? any SourceProviding else {
        throw FixContextError.sourceUnavailable
      }
      return try provider.source
    }
  }

  /// The whole captured file containing the offender.
  ///
  /// - Throws: The same errors as ``source``.
  public var file: SourceSlice {
    get throws { try source.file }
  }

  /// The codebase that produced the checked selection.
  ///
  /// Manually constructed and decoded violations have no originating codebase.
  ///
  /// - Throws: ``FixContextError/codebaseUnavailable`` when the violations
  ///   have no originating codebase.
  public var codebase: Codebase {
    get throws(FixContextError) {
      guard let queryCodebase else {
        throw FixContextError.codebaseUnavailable
      }
      return queryCodebase
    }
  }
}

/// An error when a correction context has no source provider or codebase.
public enum FixContextError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// The offender does not conform to ``/BylawsSemantics/SourceProviding``.
  case sourceUnavailable

  /// The violations have no originating codebase.
  case codebaseUnavailable

  /// A description of the context error and how to resolve it.
  public var description: String {
    switch self {
    case .sourceUnavailable:
      "FixContext must contain an offender that provides source. Select a parsed source value."
    case .codebaseUnavailable:
      "FixContext must contain a codebase. Create violations from a codebase selection."
    }
  }
}

extension Violations {
  /// Returns these violations with one proposed correction per offender.
  ///
  /// The closure runs once per offender, in order. Its edits form one
  /// correction, which may span several files. An empty result leaves the
  /// offender without a correction. This method keeps the files unchanged.
  ///
  /// Ordinary CLI lint runs skip this closure and return no corrections.
  /// Correction previews, autocorrection, direct library calls and plain
  /// `swift test` runs evaluate it. Keep the check's criteria outside the
  /// correction closure.
  public func withFix(
    _ title: String? = nil,
    @ArrayBuilder<SourceFix.Edit> _ makeFix: (FixContext<Element>) async throws
      -> [SourceFix.Edit]
  ) async throws -> Self {
    guard RuleRunPurpose.current == .proposeCorrections else {
      return removingCorrections()
    }
    var fixes: [SourceFix?] = []
    for offender in offenders {
      try Task.checkCancellation()
      let edits = try await makeFix(
        FixContext(offender: offender, codebase: codebase)
      )
      fixes.append(edits.isEmpty ? nil : SourceFix(title, edits: edits))
    }
    return Self(
      rule: rule,
      offenders: offenders,
      checkedCount: checkedCount,
      witnesses: witnesses,
      fixes: fixes,
      codebase: codebase,
      layoutCandidates: layoutCandidates
    )
  }
}
