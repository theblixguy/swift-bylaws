public import BylawsSemantics

/// The result of checking a rule over a selection.
///
/// A violations value holds the elements that failed the rule and renders
/// them in a readable failure message.
public struct Violations<Element: Sendable>: Sendable {
  /// The requirement that the elements failed, as an infinitive phrase.
  public let rule: String

  /// The elements that failed the rule.
  public let offenders: [Element]

  /// The number of elements the rule checked.
  public let checkedCount: Int

  package let witnesses: [DeclarationLocation?]

  /// Creates a violations value from a checked rule's results.
  public init(rule: String, offenders: [Element], checkedCount: Int) {
    self.init(
      rule: rule,
      offenders: offenders,
      checkedCount: checkedCount,
      witnesses: Array(repeating: nil, count: offenders.count)
    )
  }

  package init(
    rule: String,
    offenders: [Element],
    checkedCount: Int,
    witnesses: [DeclarationLocation?]
  ) {
    self.rule = rule
    self.offenders = offenders
    self.checkedCount = checkedCount
    self.witnesses = witnesses
  }

  /// Whether every checked element satisfied the rule.
  public var isEmpty: Bool { offenders.isEmpty }

  /// The number of elements that failed the rule.
  public var count: Int { offenders.count }
}

extension Violations {
  /// Creates violations holding the elements of `selection` that fail
  /// `matcher`.
  public init(of matcher: Matcher<Element>, in selection: Selection<Element>) {
    var offenders: [Element] = []
    var witnesses: [DeclarationLocation?] = []
    for element in selection {
      let match = matcher.match(element)
      if !match.matches {
        offenders.append(element)
        witnesses.append(match.witness)
      }
    }
    self.init(
      rule: matcher.requirementDescription,
      offenders: offenders,
      checkedCount: selection.count,
      witnesses: witnesses
    )
  }

  /// Creates violations holding the elements of `selection` that match
  /// `matcher`.
  ///
  /// Use this for a ban, where matching is the violation.
  public init(
    matching matcher: Matcher<Element>,
    in selection: Selection<Element>
  ) {
    self.init(of: !matcher, in: selection)
  }
}

extension Violations: Equatable where Element: Equatable {
  public static func == (lhs: Violations, rhs: Violations) -> Bool {
    lhs.rule == rhs.rule
      && lhs.offenders == rhs.offenders
      && lhs.checkedCount == rhs.checkedCount
  }
}

extension Violations: Hashable where Element: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(rule)
    hasher.combine(offenders)
    hasher.combine(checkedCount)
  }
}

extension Violations: Codable where Element: Codable {
  private enum CodingKeys: String, CodingKey {
    case rule
    case offenders
    case checkedCount
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rule: try container.decode(String.self, forKey: .rule),
      offenders: try container.decode([Element].self, forKey: .offenders),
      checkedCount: try container.decode(Int.self, forKey: .checkedCount)
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rule, forKey: .rule)
    try container.encode(offenders, forKey: .offenders)
    try container.encode(checkedCount, forKey: .checkedCount)
  }
}

/// A violation with the information a report displays.
///
/// Use ``Violations/erased()`` where code handles every rule the same way, such
/// as in a rule list or JSON report.
public struct Offender: Sendable, Hashable, Codable, Located,
  CustomStringConvertible
{
  /// The display text for the violation.
  public let description: String

  /// The declaration name or other stable identifier used by baselines.
  public let name: String?

  /// The position at which to report the violation.
  public let location: DeclarationLocation

  /// The absolute path of the affected file or folder, if it differs from the reporting location.
  ///
  /// Path filters, rule overrides and baselines use this path to determine
  /// where the violation applies.
  public let affectedPath: String?

  /// The check's requirement, or `nil` to report the rule's display name.
  public let requirement: String?

  /// Creates a violation with its reporting location and optional affected path.
  public init(
    description: String,
    name: String? = nil,
    location: DeclarationLocation,
    affectedPath: String? = nil,
    requirement: String? = nil
  ) {
    self.description = description
    self.name = name
    self.location = location
    self.affectedPath = affectedPath
    self.requirement = requirement
  }
}

extension Offender: Summarised {
  /// The offender's display text.
  public var summary: String { description }
}

extension Violations where Element: Located {
  /// Returns the violations with each element represented by an ``Offender``.
  public func erased() -> Violations<Offender> {
    if let alreadyErased = self as? Violations<Offender> {
      return alreadyErased
    }
    return Violations<Offender>(
      rule: rule,
      offenders: zip(offenders, witnesses).map { element, witness in
        Offender(
          description: (element as? any Summarised)?.summary
            ?? String(describing: element),
          name: (element as? any Named)?.name,
          location: witness ?? element.location
        )
      },
      checkedCount: checkedCount
    )
  }
}

extension Violations: CustomStringConvertible {
  public var description: String {
    if offenders.isEmpty {
      return "no violations of '\(rule)' (\(checkedCount) checked)"
    }
    let listing = offenders
      .map { "  - \(String(describing: $0))" }
      .joined(separator: "\n")
    let noun = offenders.count == 1 ? "violation" : "violations"
    return "\(offenders.count) \(noun) of '\(rule)':\n\(listing)"
  }
}
