/// A condition checked at a layout's final position in the source.
///
/// Line length is the longest physical line touched by the layout, including
/// surrounding source. Characters count as one column. Tabs advance to the
/// next tab stop. Empty input does not match, including a negated condition.
public struct SourceLayoutCondition: Sendable, Hashable, Codable {
  private indirect enum Expression: Sendable, Hashable, Codable {
    case maximumLineLength(lower: Int?, upper: Int?, includesUpper: Bool)
    case not(Expression)
    case all(Expression, Expression)
    case any(Expression, Expression)

    var largestBound: Int {
      switch self {
      case let .maximumLineLength(lower, upper, _):
        max(lower ?? .min, upper ?? .min)
      case let .not(value): value.largestBound
      case let .all(lhs, rhs), let .any(lhs, rhs):
        max(lhs.largestBound, rhs.largestBound)
      }
    }

    func matches(_ length: Int) -> Bool {
      switch self {
      case let .maximumLineLength(lower, upper, includesUpper):
        (lower.map { length >= $0 } ?? true)
          && (upper.map { includesUpper ? length <= $0 : length < $0 } ?? true)
      case let .not(value): !value.matches(length)
      case let .all(lhs, rhs): lhs.matches(length) && rhs.matches(length)
      case let .any(lhs, rhs): lhs.matches(length) || rhs.matches(length)
      }
    }
  }

  private let expression: Expression

  /// Matches when the longest touched line is within the closed range.
  public static func maximumLineLength(_ range: ClosedRange<Int>) -> Self {
    Self(expression: .maximumLineLength(
      lower: range.lowerBound, upper: range.upperBound, includesUpper: true
    ))
  }

  /// Matches when the longest touched line is within the half-open range.
  public static func maximumLineLength(_ range: Range<Int>) -> Self {
    Self(expression: .maximumLineLength(
      lower: range.lowerBound, upper: range.upperBound, includesUpper: false
    ))
  }

  /// Matches when the longest touched line reaches the lower bound.
  public static func maximumLineLength(_ range: PartialRangeFrom<Int>) -> Self {
    Self(expression: .maximumLineLength(
      lower: range.lowerBound, upper: nil, includesUpper: false
    ))
  }

  /// Matches when the longest touched line does not exceed the upper bound.
  public static func maximumLineLength(_ range: PartialRangeThrough<Int>)
    -> Self
  {
    Self(expression: .maximumLineLength(
      lower: nil, upper: range.upperBound, includesUpper: true
    ))
  }

  /// Matches when the longest touched line is below the upper bound.
  public static func maximumLineLength(_ range: PartialRangeUpTo<Int>) -> Self {
    Self(expression: .maximumLineLength(
      lower: nil, upper: range.upperBound, includesUpper: false
    ))
  }

  /// Matches when the condition does not match.
  public static prefix func ! (condition: Self) -> Self {
    Self(expression: .not(condition.expression))
  }

  /// Matches when both conditions match.
  public static func && (lhs: Self, rhs: Self) -> Self {
    Self(expression: .all(lhs.expression, rhs.expression))
  }

  /// Matches when either condition matches.
  public static func || (lhs: Self, rhs: Self) -> Self {
    Self(expression: .any(lhs.expression, rhs.expression))
  }

  package var largestBound: Int { expression.largestBound }

  package func matches(maximumLineLength: Int) -> Bool {
    expression.matches(maximumLineLength)
  }
}
