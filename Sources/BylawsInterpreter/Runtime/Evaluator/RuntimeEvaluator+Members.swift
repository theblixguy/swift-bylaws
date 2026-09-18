import BylawsCore
import BylawsSemantics
import Foundation

extension RuntimeEvaluator {
  func evaluateCallable(
    _ expression: RuntimeExpression,
    in environment: RuntimeEnvironment,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    guard case let .member(base, name) = expression.kind else {
      return try await evaluate(expression, in: environment, state: &state)
    }
    let receiver = try await evaluate(base, in: environment, state: &state)
    guard let receiverType = receiver.runtimeReceiver,
          let api = SupportedAPI.runtimeMethod(named: name, on: receiverType),
          let method = api.method
    else {
      return try await member(
        named: name,
        of: receiver,
        at: expression.location,
        state: &state
      )
    }
    return .boundMethod(receiver: receiver, name: method)
  }

  func member(
    named name: SupportedAPI.Member,
    of receiver: RuntimeValue,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let api = receiver.runtimeReceiver.flatMap {
      SupportedAPI.runtimeProperty(named: name, on: $0)
        ?? SupportedAPI.runtimeMethod(named: name, on: $0)
    }
    if receiver.runtimeReceiver != nil, api == nil {
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported member of this value",
        location: location
      )
    }
    if let method = api?.method {
      return .boundMethod(receiver: receiver, name: method)
    }
    if api?.canSuspend == true, state.synchronousClosureDepth > 0 {
      throw RuntimeError(
        message: "a synchronous closure cannot suspend",
        location: location
      )
    }
    switch receiver {
    case let .url(value):
      switch name {
      case .path: return .string(value.path)
      case .lastPathComponent: return .string(value.lastPathComponent)
      case .pathExtension: return .string(value.pathExtension)
      default: break
      }
    case let .dictionary(values):
      switch name {
      case .count: return .integer(values.count)
      case .isEmpty: return .boolean(values.isEmpty)
      default: break
      }
    case let .dependencyGroup(group):
      switch name {
      case .name: return .string(group.name)
      case .files: return .array(group.files.map(RuntimeValue.string))
      default: break
      }
    case let .array(values) where name == .first:
      return .optional(values.first)
    case let .array(values), let .set(values):
      switch name {
      case .count: return .integer(values.count)
      case .isEmpty: return .boolean(values.isEmpty)
      default: break
      }
    case let .string(value):
      switch name {
      case .count: return .integer(value.count)
      case .isEmpty: return .boolean(value.isEmpty)
      case .description: return receiver
      case .first:
        return .optional(value.first.map { .string(String($0)) })
      default: break
      }
    case let .integerRange(value):
      switch name {
      case .count: return .integer(value.count)
      case .isEmpty: return .boolean(value.isEmpty)
      case .lowerBound: return .integer(value.lowerBound)
      case .upperBound: return .integer(value.upperBound)
      default: break
      }
    case let .manifestList(value):
      switch name {
      case .knownValues: return .array(value.knownValues)
      case .conditionalValues: return .array(value.conditionalValues)
      case .possibleValues: return .array(value.possibleValues)
      case .unresolvedValues:
        return .array(value.unresolvedValues.map(RuntimeValue.model))
      case .isComplete: return .boolean(value.isComplete)
      case .values: return .optional(value.values.map(RuntimeValue.array))
      default: break
      }
    case let .optional(value):
      guard let value else { return .optional(nil) }
      return try await member(
        named: name,
        of: value,
        at: location,
        state: &state
      ).optionalChained
    case let .codebase(codebase):
      return try await codebaseMember(
        name,
        codebase: codebase,
        at: location
      )
    case let .selection(selection):
      switch name {
      case .count: return .integer(selection.elements.count)
      case .isEmpty: return .boolean(selection.elements.isEmpty)
      case .first:
        return .optional(selection.elements.first.map(RuntimeValue.model))
      case .queryDescription: return .string(selection.queryDescription)
      default: break
      }
    case let .model(value):
      if let property = modelMember(name, of: value) {
        return property
      }
    case let .matcher(matcher):
      if name == .requirementDescription {
        return .string(matcher.requirement)
      }
    case let .violations(violations):
      switch name {
      case .count: return .integer(violations.offenders.count)
      case .isEmpty: return .boolean(violations.offenders.isEmpty)
      case .rule: return .string(violations.rule)
      case .checkedCount: return .integer(violations.checkedCount)
      case .offenders:
        return .array(violations.offenders.map(RuntimeValue.model))
      default: break
      }
    case let .findings(findings):
      switch name {
      case .checks:
        return .array(findings.checks.map { check in
          .violations(RuntimeViolations(
            rule: check.rule,
            offenders: check.offenders.map(RuntimeModelValue.offender),
            checkedCount: check.checkedCount
          ))
        })
      case .violations:
        return .violations(RuntimeViolations(
          rule: findings.violations.rule,
          offenders: findings.violations.offenders
            .map(RuntimeModelValue.offender),
          checkedCount: findings.violations.checkedCount
        ))
      case .warnings:
        return .array(findings.warnings.map { .model(.check(.warning($0))) })
      default: break
      }
    case .genericType(name: let type, arguments: _):
      if name == .selfType { return receiver }
      if name == .kindType,
         let nestedType = SupportedAPI.ModelType(rawValue: type)?
         .nestedStaticMemberType
      {
        return .genericType(
          name: nestedType.rawValue,
          arguments: []
        )
      }
      if let owner = SupportedAPI.StaticMemberType(rawValue: type)?.owner,
         let literal = SupportedAPI.MemberLiteral(rawValue: name.rawValue),
         literal.owners.contains(owner)
      {
        return .member(literal)
      }
    default: break
    }
    throw RuntimeError(
      message: "'\(name.rawValue)' is not a supported member of this value",
      location: location
    )
  }
}

extension SupportedAPI.RuntimeMemberAPI {
  fileprivate var method: SupportedAPI.Method? {
    guard case let .method(call) = kind else { return nil }
    return call.method
  }
}

extension RuntimeValue {
  fileprivate var runtimeReceiver: SupportedAPI.RuntimeReceiver? {
    switch self {
    case .url: .url
    case .dictionary: .dictionary
    case .array: .array
    case .set: .set
    case .string: .string
    case .codebase: .codebase
    case .dependencyGroup: .dependencyGroup
    case .selection: .selection
    case let .model(value): .model(value.modelType)
    case .matcher: .matcher
    case .projectIndex: .projectIndex
    case .symbolRoles: .symbolRoles
    case .violations: .violations
    case .findings: .findings
    case .ruleResults: .ruleResults
    case .integerRange: .integerRange
    case .manifestList: .manifestList
    case .genericType("Matcher", _): .staticType("Matcher")
    default: nil
    }
  }
}
