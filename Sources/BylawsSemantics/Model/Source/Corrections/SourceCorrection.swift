/// The result of preparing a source correction.
public struct SourceCorrection: Sendable {
  /// Whether the source matches the operation and can be corrected.
  public enum Outcome: Sendable, Equatable {
    /// The operation does not apply to the selected source.
    case notApplicable
    /// The source already has the requested form.
    case satisfied
    /// The source fails the requirement.
    case violation
    /// The available source cannot establish whether the operation applies.
    case undetermined
  }

  /// The result of checking the selected source.
  public let outcome: Outcome

  /// The proposed correction, including unchanged layouts needed by other edits.
  public let fix: SourceFix?

  /// Why a correction or its applicability could not be established.
  public let reason: String?

  /// Creates a result from edits against captured source.
  public init(edits: [SourceFix.Edit]) {
    self.init(SourceFix(edits: edits))
  }

  /// Creates a result from a proposed correction.
  public init(_ fix: SourceFix) {
    outcome = fix.edits.contains {
      !$0.source.text.utf8.elementsEqual($0.replacement.utf8)
    } ? .violation : .satisfied
    self.fix = fix
    reason = nil
  }

  package var fixOmittingUnchangedEdits: SourceFix? {
    fix.map {
      SourceFix(
        $0.title,
        proposedEdits: $0.edits,
        layoutCandidates: $0.layoutCandidates
      )
    }
  }

  package func proposedFix(titled title: String?) -> SourceFix? {
    guard let fix, !fix.edits.isEmpty || !fix.layoutCandidates.isEmpty
    else { return nil }
    return SourceFix(
      title ?? fix.title, edits: fix.edits,
      layoutCandidates: fix.layoutCandidates
    )
  }

  private init(outcome: Outcome, reason: String? = nil) {
    self.outcome = outcome
    fix = nil
    self.reason = reason
  }

  /// A result for source outside the operation's matching conditions.
  public static var notApplicable: Self { Self(outcome: .notApplicable) }

  /// A result for source that already meets the requirement.
  public static var satisfied: Self { Self(outcome: .satisfied) }

  /// Records a known violation for which a correction cannot be prepared.
  public static func unavailable(_ reason: String) -> Self {
    Self(outcome: .violation, reason: reason)
  }

  /// Records why the operation's applicability cannot be established.
  public static func undetermined(_ reason: String) -> Self {
    Self(outcome: .undetermined, reason: reason)
  }

  /// Combines operations into one proposed correction.
  ///
  /// An undetermined operation takes precedence. A known violation without a
  /// correction withholds all proposed edits.
  public init(combining corrections: [Self]) {
    if let unresolved = corrections
      .first(where: { $0.outcome == .undetermined })
    {
      self = unresolved
      return
    }
    if let unavailable = corrections.first(where: {
      $0.outcome == .violation && $0.fix == nil
    }) {
      self = unavailable
      return
    }
    let fixes = corrections.compactMap(\.fix)
    guard !fixes.isEmpty else {
      self = corrections.contains { $0.outcome == .satisfied }
        ? .satisfied : .notApplicable
      return
    }
    if fixes.count == 1 {
      self.init(fixes[0])
    } else {
      self.init(SourceFix(
        edits: fixes.flatMap(\.edits),
        layoutCandidates: fixes.flatMap(\.layoutCandidates)
      ))
    }
  }
}

/// A value that describes the result of preparing a source correction.
public protocol SourceCorrectionProviding: Sendable {
  /// The correction and whether it applies to the selected source.
  var correction: SourceCorrection { get }
}

extension SourceCorrection: SourceCorrectionProviding {
  /// This correction result.
  public var correction: Self { self }
}

extension SourceFix: SourceCorrectionProviding {
  /// The result of proposing this fix.
  public var correction: SourceCorrection { SourceCorrection(self) }
}

extension SourceFix.Edit: SourceCorrectionProviding {
  /// The result of proposing this replacement.
  public var correction: SourceCorrection { SourceCorrection(edits: [self]) }
}

extension Array: SourceCorrectionProviding
  where Element: SourceCorrectionProviding
{
  /// The combined correction for these operations.
  public var correction: SourceCorrection {
    SourceCorrection(combining: map(\.correction))
  }
}
