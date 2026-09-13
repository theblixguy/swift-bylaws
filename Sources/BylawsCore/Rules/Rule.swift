public import BylawsSemantics
public import Foundation

/// One architectural rule with a name, an enforcement level and a body
/// that returns a check result.
public struct Rule: Sendable, Identifiable, Located {
  /// The stable identifier that overrides, baselines and command-line
  /// flags reference.
  ///
  /// References remain valid when the display name changes. A rule declared
  /// with a name alone uses that name as its id.
  public struct ID: Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
  {
    /// The identifier's text.
    public let rawValue: String

    /// Creates an id from its text.
    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(value)
    }

    public init(from decoder: any Decoder) throws {
      self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }

    public var description: String { rawValue }
  }

  /// The stable identifier used by overrides, baselines and CLI selection.
  public let id: ID

  /// The display name, written as an infinitive requirement phrase.
  public let name: String

  /// The level that decides whether violations fail the run or remain
  /// visible as non-failing issues.
  public let enforcement: Enforcement

  /// The guidance a report prints beside the rule's violations, such as
  /// where the offending code belongs, or `nil` when the rule's name
  /// says enough.
  public let hint: String?

  /// The position of the rule's declaration, which is its `Rule(...)`
  /// line in a `Bylaws.swift` file or the code that constructed it.
  public let location: DeclarationLocation

  /// One warning a run of a rule reports beside its violations, such as
  /// a layer whose globs match no file.
  public struct Warning: Sendable, Hashable, Codable {
    /// The problem, in one sentence.
    public let message: String

    /// The position the warning points at.
    public let location: DeclarationLocation

    /// Creates a warning from its message and position.
    public init(message: String, location: DeclarationLocation) {
      self.message = message
      self.location = location
    }
  }

  private let body: @Sendable () async throws -> Findings

  /// Creates a rule that reports the check results in its body.
  ///
  /// Check expressions run in order and retain their individual requirements.
  /// An explicit `return` reports only its result.
  public init(
    _ id: ID,
    _ name: String,
    enforcement: Enforcement = .enforced,
    hint: String? = nil,
    location: DeclarationLocation? = nil,
    filePath: String = #filePath,
    line: Int = #line,
    @RuleResultBuilder body: @escaping @Sendable () async throws
      -> some RuleResult
  ) {
    let location = location ?? .callSite(filePath: filePath, line: line)
    self.id = id
    self.name = name
    self.enforcement = enforcement
    self.hint = hint
    self.location = location
    self.body = { try await body().findings(reportedAt: location) }
  }

  /// Creates a rule whose display name is also its id.
  public init(
    _ name: String,
    enforcement: Enforcement = .enforced,
    hint: String? = nil,
    location: DeclarationLocation? = nil,
    filePath: String = #filePath,
    line: Int = #line,
    @RuleResultBuilder body: @escaping @Sendable () async throws
      -> some RuleResult
  ) {
    self.init(
      ID(name),
      name,
      enforcement: enforcement,
      hint: hint,
      location: location,
      filePath: filePath,
      line: line,
      body: body
    )
  }

  /// Returns the violations from one run of the rule.
  public func violations() async throws(RuleError) -> Violations<Offender> {
    try await findings().violations
  }

  /// Returns the violations and warnings from one run of the rule.
  public func findings() async throws(RuleError) -> Findings {
    do {
      let (findings, queryWarnings) = try await QueryWarnings.collecting(body)
      guard !queryWarnings.isEmpty else { return findings }
      return Findings(
        checks: findings.checks,
        warnings: findings.warnings + queryWarnings
      )
    } catch {
      throw RuleError(rule: id, cause: RuleError.Cause(error))
    }
  }
}

extension Rule: CustomStringConvertible {
  public var description: String { name }
}

/// The failure of a rule that could not run.
public struct RuleError: Error, Sendable, CustomStringConvertible {
  /// The reason a rule body stopped.
  ///
  /// Later versions may add cases.
  @nonexhaustive
  public enum Cause: Sendable, CustomStringConvertible {
    /// The task that ran the rule was cancelled.
    case cancelled

    /// The codebase could not be read or parsed.
    case codebase(CodebaseError)

    /// A layering check could not run.
    case layering(LayeringCheckError)

    /// A failure the rule body threw itself.
    case other(any Error)

    /// Creates the cause that classifies an error a rule body threw.
    public init(_ error: any Error) {
      self = switch error {
      case is CancellationError: .cancelled
      case let error as CodebaseError: .codebase(error)
      case let error as LayeringCheckError: .layering(error)
      default: .other(error)
      }
    }

    public var description: String {
      switch self {
      case .cancelled: "the run was cancelled"
      case let .codebase(error): error.description
      case let .layering(error): error.description
      case let .other(error): error.reportableDescription
      }
    }
  }

  /// The rule that failed to run.
  public let rule: Rule.ID

  /// The failure that stopped the rule.
  public let cause: Cause

  /// Creates a rule error from the failed rule and its cause.
  public init(rule: Rule.ID, cause: Cause) {
    self.rule = rule
    self.cause = cause
  }

  public var description: String {
    "rule '\(rule)' could not run: \(cause)"
  }
}

extension RuleError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
