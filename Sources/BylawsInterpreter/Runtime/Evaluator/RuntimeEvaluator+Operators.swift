import BylawsSemantics
import Foundation

extension RuntimeEvaluator {
  func binary(
    left: RuntimeExpression,
    operator operatorName: String,
    right: RuntimeExpression,
    environment: RuntimeEnvironment,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let leftValue = try await evaluate(
      left,
      in: environment,
      state: &state
    )
    if operatorName == "&&", case let .boolean(value) = leftValue, !value {
      return .boolean(false)
    }
    if operatorName == "||", case let .boolean(value) = leftValue, value {
      return .boolean(true)
    }
    if operatorName == "??", case let .optional(value) = leftValue {
      if let value { return value }
      return try await evaluate(right, in: environment, state: &state)
    }
    let rightValue = try await evaluate(
      right,
      in: environment,
      state: &state
    )
    return try applyBinary(
      operatorName,
      left: leftValue,
      right: rightValue,
      at: left.location
    )
  }

  private func applyBinary(
    _ operatorName: String,
    left: RuntimeValue,
    right: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue {
    if case let .matcher(leftMatcher) = left,
       case let .matcher(rightMatcher) = right
    {
      if let leftSubject = leftMatcher.subjectType,
         let rightSubject = rightMatcher.subjectType,
         leftSubject != rightSubject
      {
        throw RuntimeError(
          message: "'\(operatorName)' cannot combine Matcher<\(leftSubject.rawValue)> and Matcher<\(rightSubject.rawValue)>",
          location: location
        )
      }
      switch operatorName {
      case "&&":
        return .matcher(
          RuntimeMatcher(
            subjectType: leftMatcher.subjectType ?? rightMatcher.subjectType,
            requirement: "\(leftMatcher.requirement) and \(rightMatcher.requirement)",
            predicate: .and(leftMatcher, rightMatcher)
          )
        )
      case "||":
        return .matcher(
          RuntimeMatcher(
            subjectType: leftMatcher.subjectType ?? rightMatcher.subjectType,
            requirement: "\(leftMatcher.requirement) or \(rightMatcher.requirement)",
            predicate: .or(leftMatcher, rightMatcher)
          )
        )
      default: break
      }
    }
    if let result = try numericOperation(
      operatorName,
      left: left,
      right: right,
      at: location
    ) {
      return result
    }

    switch (operatorName, left, right) {
    case let ("&&", .boolean(lhs), .boolean(rhs)):
      return .boolean(lhs && rhs)
    case let ("||", .boolean(lhs), .boolean(rhs)):
      return .boolean(lhs || rhs)
    case ("==", _, _): return .boolean(equals(left, right))
    case ("!=", _, _): return .boolean(!equals(left, right))
    case let ("<", .string(lhs), .string(rhs)):
      return .boolean(lhs < rhs)
    case let ("<=", .string(lhs), .string(rhs)):
      return .boolean(lhs <= rhs)
    case let (">", .string(lhs), .string(rhs)):
      return .boolean(lhs > rhs)
    case let (">=", .string(lhs), .string(rhs)):
      return .boolean(lhs >= rhs)
    case let ("+", .string(lhs), .string(rhs)):
      return .string(lhs + rhs)
    case let ("+", .array(lhs), .array(rhs)):
      return .array(lhs + rhs)
    default:
      throw RuntimeError(
        message: "'\(operatorName)' does not apply to these values",
        location: location
      )
    }
  }

  func prefix(
    _ operatorName: String,
    value: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue {
    switch (operatorName, value) {
    case let ("!", .boolean(value)):
      return .boolean(!value)
    case let ("!", .matcher(matcher)):
      return .matcher(
        RuntimeMatcher(
          subjectType: matcher.subjectType,
          requirement: "not \(matcher.requirement)",
          predicate: .not(matcher)
        )
      )
    case let ("-", .integer(value)):
      let negation = 0.subtractingReportingOverflow(value)
      guard !negation.overflow else {
        throw RuntimeError(
          message: "integer negation exceeds the supported range",
          location: location
        )
      }
      return .integer(negation.partialValue)
    case let ("-", .double(value)):
      return .double(-value)
    default:
      throw RuntimeError(
        message: "'\(operatorName)' does not apply to this value",
        location: location
      )
    }
  }

  func equals(_ left: RuntimeValue, _ right: RuntimeValue) -> Bool {
    switch (left, right) {
    case let (.url(lhs), .url(rhs)): lhs == rhs
    case let (.dictionary(lhs), .dictionary(rhs)):
      lhs.count == rhs.count && lhs.allSatisfy { key, value in
        rhs[key].map { equals(value, $0) } ?? false
      }
    case let (.boolean(lhs), .boolean(rhs)): lhs == rhs
    case let (.integer(lhs), .integer(rhs)): lhs == rhs
    case let (.integer(lhs), .double(rhs)): Double(lhs) == rhs
    case let (.double(lhs), .integer(rhs)): lhs == Double(rhs)
    case let (.integerRange(lhs), .integerRange(rhs)): lhs == rhs
    case let (.double(lhs), .double(rhs)): lhs == rhs
    case let (.string(lhs), .string(rhs)): lhs == rhs
    case let (.member(lhs), .member(rhs)): lhs == rhs
    case let (.model(lhs), .model(rhs)): lhs == rhs
    case let (.codebase(lhs), .codebase(rhs)): lhs == rhs
    case let (.dependencyGroup(lhs), .dependencyGroup(rhs)): lhs == rhs
    case let (.layering(lhs), .layering(rhs)): lhs == rhs
    case let (.violations(lhs), .violations(rhs)): lhs == rhs
    case let (.symbolRoles(lhs), .symbolRoles(rhs)): lhs == rhs
    case let (.manifestList(lhs), .manifestList(rhs)):
      equals(.array(lhs.knownValues), .array(rhs.knownValues))
        && equals(.array(lhs.conditionalValues), .array(rhs.conditionalValues))
        && lhs.unresolvedValues == rhs.unresolvedValues
    case let (.array(lhs), .array(rhs)):
      lhs.count == rhs.count
        && zip(lhs, rhs).allSatisfy { pair in
          equals(pair.0, pair.1)
        }
    case let (.set(lhs), .set(rhs)):
      lhs.count == rhs.count
        && lhs.allSatisfy { value in
          rhs.contains { equals(value, $0) }
        }
    case (.void, .void): true
    case (.optional(nil), .optional(nil)): true
    case (.optional(nil), .optional(.some)),
         (.optional(.some), .optional(nil)): false
    case let (.optional(lhs?), .optional(rhs?)): equals(lhs, rhs)
    case let (.optional(lhs?), rhs): equals(lhs, rhs)
    case let (lhs, .optional(rhs?)): equals(lhs, rhs)
    default: false
    }
  }

  private func numericValues(
    _ left: RuntimeValue,
    _ right: RuntimeValue
  ) -> (Double, Double)? {
    let lhs: Double? = switch left {
    case let .integer(value): Double(value)
    case let .double(value): value
    default: nil
    }
    let rhs: Double? = switch right {
    case let .integer(value): Double(value)
    case let .double(value): value
    default: nil
    }
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
  }

  private func numericOperation(
    _ operatorName: String,
    left: RuntimeValue,
    right: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue? {
    if case let .integer(lhs) = left,
       case let .integer(rhs) = right
    {
      switch operatorName {
      case "<": return .boolean(lhs < rhs)
      case "<=": return .boolean(lhs <= rhs)
      case ">": return .boolean(lhs > rhs)
      case ">=": return .boolean(lhs >= rhs)
      case "+":
        let addition = lhs.addingReportingOverflow(rhs)
        guard !addition.overflow else {
          throw RuntimeError(
            message: "integer addition exceeds the supported range",
            location: location
          )
        }
        return .integer(addition.partialValue)
      default: return nil
      }
    }
    guard let (lhs, rhs) = numericValues(left, right) else { return nil }
    return switch operatorName {
    case "<": .boolean(lhs < rhs)
    case "<=": .boolean(lhs <= rhs)
    case ">": .boolean(lhs > rhs)
    case ">=": .boolean(lhs >= rhs)
    case "+": .double(lhs + rhs)
    default: nil
    }
  }

  func string(
    from value: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> String {
    switch value {
    case let .string(value): value
    case let .integer(value): String(value)
    case let .integerRange(value): String(describing: value)
    case let .double(value): String(value)
    case let .boolean(value): String(value)
    case let .member(value): value.rawValue
    case let .model(value): String(describing: value)
    case let .set(values):
      "[" + (try values.map { value throws(RuntimeError) in
        try string(from: value, at: location)
      })
      .joined(separator: ", ") + "]"
    case let .optional(value?): try string(from: value, at: location)
    case .optional(nil): "nil"
    default:
      throw RuntimeError(
        message: "this value cannot appear in a string interpolation",
        location: location
      )
    }
  }
}
