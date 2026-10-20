import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func sourceMethod(
    _ name: SupportedAPI.Method,
    value: SourceSlice,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    do {
      switch name {
      case .replacement:
        try arguments.requireLabels([.with], for: name)
        return .sourceEdit(value.replacement(with: try arguments.string(at: 0)))
      case .matches:
        try arguments.requireLabels([.of], for: name)
        guard case let .regex(pattern) = try arguments.value(at: 0) else {
          throw RuntimeError(
            message: "matches takes one Regex",
            location: arguments.location
          )
        }
        let regex = try pattern.compiled(at: arguments.location)
        return .array(value.matches(of: regex).map(RuntimeValue.sourceSlice))
      case .slice:
        try arguments.requireLabels([nil], for: name)
        guard case let .integerRange(range) = try arguments.value(at: 0) else {
          throw RuntimeError(
            message: "slice takes one Range<Int>",
            location: arguments.location
          )
        }
        return .sourceSlice(try value.slice(range))
      default:
        throw RuntimeError(
          message: "'\(name.rawValue)' is not a supported SourceSlice method",
          location: arguments.location
        )
      }
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }

  func attachingFixes(
    to violations: RuntimeViolations,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let count = arguments.values.count
    guard count == 1 || count == 2,
          arguments.values.allSatisfy({ $0.label == nil })
    else {
      throw RuntimeError(
        message: "withFix takes an optional title and one fix closure",
        location: arguments.location
      )
    }
    let title: String? = if count == 1 {
      nil
    } else {
      switch try arguments.value(at: 0) {
      case let .string(value), let .optional(.string(value)): value
      case .optional(nil): nil
      default:
        throw RuntimeError(
          message: "the fix title must be String",
          location: arguments.location
        )
      }
    }
    let callable = try arguments.value(at: count - 1)
    var fixes: [SourceFix?] = []
    for index in violations.offenders.indices {
      try step(at: arguments.location, state: &state)
      let offender = violations.offenders[index]
      if let reported = offender.offender,
         excludedSubtrees?.contains(
           reported.affectedPath ?? violations.witnesses[index]?.filePath
             ?? reported.location.filePath
         ) == true
      {
        fixes.append(nil)
        continue
      }
      let context = RuntimeValue.fixContext(RuntimeFixContext(
        offender: offender,
        codebase: violations.codebase
      ))
      let result: RuntimeValue = switch callable {
      case let .closure(closure):
        try await invoke(
          closure, arguments: [context], builder: .edits, state: &state
        )
      case let .function(function):
        try await invoke(
          callable,
          arguments: [(
            function.definition.parameters.first?.externalName,
            context
          )],
          trailingClosure: nil,
          at: arguments.location,
          state: &state
        )
      default:
        throw RuntimeError(
          message: "withFix takes a fix closure or function",
          location: arguments.location
        )
      }
      guard case let .array(values) = result else {
        throw RuntimeError(
          message: "withFix must return an edit array",
          location: arguments.location
        )
      }
      let edits = try values
        .map { value throws(RuntimeError) -> SourceFix.Edit in
          guard case let .sourceEdit(edit) = value else {
            throw RuntimeError(
              message: "withFix takes SourceFix.Edit values or edit arrays",
              location: arguments.location
            )
          }
          return edit
        }
      fixes.append(edits.isEmpty ? nil : SourceFix(title, edits: edits))
    }
    return .violations(RuntimeViolations(
      rule: violations.rule,
      offenders: violations.offenders,
      checkedCount: violations.checkedCount,
      witnesses: violations.witnesses,
      fixes: fixes,
      codebase: violations.codebase
    ))
  }
}
