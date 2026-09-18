import BylawsCore
import BylawsSemantics
import BylawsSyntax
import Foundation

extension RuntimeEvaluator {
  private func unique(_ values: [RuntimeValue]) -> [RuntimeValue] {
    values.reduce(into: []) { result, value in
      if !result.contains(where: { equals($0, value) }) { result.append(value) }
    }
  }

  func construct(
    type name: String,
    typeArguments: [SupportedAPI.RuntimeType],
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    guard let constructor = SupportedAPI.Constructor(rawValue: name) else {
      throw RuntimeError(
        message: "portable rules do not support this '\(name)' initialiser",
        location: arguments.location
      )
    }
    switch constructor {
    case .url:
      return .url(URL(fileURLWithPath: try arguments.string(at: 0)))
    case .dictionary:
      return try await groupDictionary(arguments: arguments, state: &state)
    case .dependencyGroup:
      return .dependencyGroup(DependencyGroup(
        try arguments.string(at: 0), files: try arguments.strings(at: 1)
      ))
    case .layer: return try constructLayer(arguments)
    case .layering:
      if arguments.values.count == 1,
         case let .closure(body) = arguments.values[0].value
      {
        let result = try await invoke(
          body,
          arguments: [],
          builder: .layers,
          state: &state
        )
        if case let .array(values) = result {
          return try RuntimeBuilder.layers.combine(
            values,
            at: arguments.location
          )
        }
        return result
      }
      return try RuntimeBuilder.layers.combine(
        arguments.values.map(\.value),
        at: arguments.location
      )
    case .ruleResults:
      return try RuntimeBuilder.checks.combine(
        arguments.values.map(\.value),
        at: arguments.location
      )
    case .matcher:
      guard typeArguments.count == 1,
            case let .model(subject) = typeArguments[0]
      else {
        throw RuntimeError(
          message: "Matcher takes one supported subject type",
          location: arguments.location
        )
      }
      if arguments.values.count == 1 {
        return .matcher(try matcherValue(
          from: arguments.value(at: 0),
          location: arguments.location
        ))
      }
      let predicate = try arguments.closure(at: 1)
      return .matcher(
        RuntimeMatcher(
          subjectType: subject,
          requirement: try arguments.string(at: 0),
          predicate: .closure(predicate)
        )
      )
    case .rule:
      return try constructRule(arguments)
    case .array:
      if typeArguments.isEmpty || typeArguments == [.rule],
         arguments.values.count == 1
      {
        return try await invoke(
          arguments.closure(at: 0),
          arguments: [],
          builder: .rules,
          state: &state
        )
      }
      return .array([])
    case .set:
      if arguments.values.isEmpty { return .set([]) }
      return .set(unique(try arguments.array(at: 0)))
    case .trivia:
      let pieces = try arguments.array(at: 0)
        .map { value throws(RuntimeError) in
          guard case let .model(.syntaxTriviaPiece(piece)) = value else {
            throw RuntimeError(
              message: "Trivia pieces must come from syntax trivia",
              location: arguments.location
            )
          }
          return piece
        }
      return .string(Trivia(pieces: pieces).description)
    case .violations:
      let values = try arguments.array(at: 1)
      let offenders: [RuntimeModelValue] = values.compactMap { value in
        guard case let .model(model) = value, model.offender != nil else {
          return nil
        }
        return model
      }
      guard offenders.count == values.count else {
        throw RuntimeError(
          message: "each Violations offender must have a source location",
          location: arguments.location
        )
      }
      return .violations(
        RuntimeViolations(
          rule: try arguments.string(at: 0),
          offenders: offenders,
          checkedCount: try arguments.integer(at: 2)
        )
      )
    }
  }

  private func constructRule(
    _ arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    guard let final = arguments.values.last,
          final.label == nil,
          case let .closure(body) = final.value
    else {
      throw RuntimeError(
        message: "Rule takes one trailing body closure",
        location: arguments.location
      )
    }
    let metadata = arguments.values.dropLast()
    var positional: [String] = []
    var enforcement = Enforcement.enforced
    var hint: String?
    for argument in metadata {
      switch argument.label
        .flatMap(SupportedAPI.ArgumentLabel.init(rawValue:))
      {
      case nil:
        guard case let .string(value) = argument.value else {
          throw RuntimeError(
            message: "Rule takes a string ID and a string display name",
            location: arguments.location
          )
        }
        positional.append(value)
      case .enforcement:
        guard case let .member(value) = argument.value,
              let parsed = Enforcement(rawValue: value.rawValue)
        else {
          throw RuntimeError(
            message: "'enforcement' must be advisory or enforced",
            location: arguments.location
          )
        }
        enforcement = parsed
      case .hint:
        guard case let .string(value) = argument.value else {
          throw RuntimeError(
            message: "'hint' must be a String",
            location: arguments.location
          )
        }
        hint = value
      default:
        throw RuntimeError(
          message: "portable rules do not support this Rule argument",
          location: arguments.location
        )
      }
    }
    guard positional.count == 1 || positional.count == 2 else {
      throw RuntimeError(
        message: "Rule takes an ID and an optional display name",
        location: arguments.location
      )
    }
    return .rule(
      RuntimeRule(
        id: positional[0],
        name: positional.count == 2 ? positional[1] : positional[0],
        enforcement: enforcement,
        hint: hint,
        body: body,
        location: arguments.location
      )
    )
  }
}
