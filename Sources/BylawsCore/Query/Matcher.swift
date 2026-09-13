package import BylawsSemantics

/// A composable, self-describing predicate over a single subject.
///
/// The same matcher works as a filter (`selection.where(_:)`) and as a rule
/// (`selection.violations(of:)`). Its requirement phrase renders in failure
/// messages. Write custom matchers with the requirement-and-closure
/// initialiser:
///
/// ```swift
/// Matcher<Class>("declare 10 functions or fewer") { $0.functions.count <= 10 }
/// ```
public struct Matcher<Subject>: Sendable {
  typealias Witness = @Sendable (Subject) -> DeclarationLocation?

  indirect enum Criterion: Sendable {
    case predicate(String, @Sendable (Subject) -> Bool)
    case witnessed(String, Witness)
    case evaluated(String, @Sendable (Subject) -> Match)
    case and(Criterion, Criterion)
    case or(Criterion, Criterion)
    case not(Criterion)
  }

  let criterion: Criterion

  init(criterion: Criterion) {
    self.criterion = criterion
  }

  /// Creates a matcher from an infinitive requirement phrase, such as
  /// `"inherit from 'BaseViewModel'"`, and a predicate.
  public init(
    _ requirement: String,
    _ predicate: @escaping @Sendable (Subject) -> Bool
  ) {
    criterion = .predicate(requirement, predicate)
  }

  init(_ requirement: String, witnessedBy witness: @escaping Witness) {
    criterion = .witnessed(requirement, witness)
  }

  /// Checks whether `subject` satisfies this matcher.
  public func callAsFunction(_ subject: Subject) -> Bool {
    match(subject).matches
  }

  /// The requirement this matcher checks, as an infinitive phrase.
  public var requirementDescription: String {
    Self.describe(criterion)
  }

  /// A matcher satisfied only when both matchers are satisfied.
  public static func && (lhs: Matcher, rhs: Matcher) -> Matcher {
    Matcher(criterion: .and(lhs.criterion, rhs.criterion))
  }

  /// A matcher satisfied when either matcher is satisfied.
  public static func || (lhs: Matcher, rhs: Matcher) -> Matcher {
    Matcher(criterion: .or(lhs.criterion, rhs.criterion))
  }

  /// A matcher satisfied when `matcher` is unsatisfied.
  public static prefix func ! (matcher: Matcher) -> Matcher {
    Matcher(criterion: .not(matcher.criterion))
  }

  package struct Match: Sendable {
    package let matches: Bool
    package let witness: DeclarationLocation?
  }

  package func match(_ subject: Subject) -> Match {
    Self.match(criterion, on: subject)
  }

  private static func match(
    _ criterion: Criterion,
    on subject: Subject
  ) -> Match {
    switch criterion {
    case let .predicate(_, predicate):
      return Match(matches: predicate(subject), witness: nil)
    case let .witnessed(_, witness):
      let location = witness(subject)
      return Match(matches: location != nil, witness: location)
    case let .evaluated(_, evaluate):
      return evaluate(subject)
    case let .and(lhs, rhs):
      let left = match(lhs, on: subject)
      guard left.matches else { return left }
      let right = match(rhs, on: subject)
      return right.matches
        ? Match(matches: true, witness: left.witness ?? right.witness)
        : right
    case let .or(lhs, rhs):
      let left = match(lhs, on: subject)
      return left.matches ? left : match(rhs, on: subject)
    case let .not(inner):
      let result = match(inner, on: subject)
      return Match(matches: !result.matches, witness: result.witness)
    }
  }

  private static func describe(
    _ criterion: Criterion, insideOr: Bool = false
  ) -> String {
    switch criterion {
    case let .predicate(requirement, _), let .witnessed(requirement, _),
         let .evaluated(requirement, _):
      return requirement
    case let .and(lhs, rhs):
      let joined = "\(describe(lhs, insideOr: insideOr)) and \(describe(rhs, insideOr: insideOr))"
      return insideOr ? "(\(joined))" : joined
    case let .or(lhs, rhs):
      return "(\(describe(lhs, insideOr: true)) or \(describe(rhs, insideOr: true)))"
    case let .not(.predicate(requirement, _)), let .not(.witnessed(
      requirement,
      _
    )),
    let .not(.evaluated(requirement, _)):
      return "not \(requirement)"
    case let .not(.or(lhs, rhs)):
      return "not \(describe(.or(lhs, rhs)))"
    case let .not(inner):
      return "not (\(describe(inner)))"
    }
  }
}

extension Matcher: CustomStringConvertible {
  public var description: String { requirementDescription }
}
