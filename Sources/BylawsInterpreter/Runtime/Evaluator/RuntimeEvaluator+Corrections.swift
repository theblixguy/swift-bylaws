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
      case .hasLine:
        let hasTabWidth = arguments.values.count == 2
        try arguments.requireLabels(
          hasTabWidth ? [.exceeding, .tabWidth] : [.exceeding],
          for: name
        )
        return .boolean(value.hasLine(
          exceeding: try arguments.integer(at: 0),
          tabWidth: hasTabWidth ? try arguments.integer(at: 1) : 8
        ))
      case .replacement:
        if arguments.hasLabels([.applying]) {
          guard case let .array(values) = try arguments.value(at: 0) else {
            throw RuntimeError(
              message: "replacement takes an array of source edits",
              location: arguments.location
            )
          }
          let edits = try values
            .map { value throws(RuntimeError) -> SourceFix.Edit in
              guard case let .sourceEdit(edit) = value else {
                throw RuntimeError(
                  message: "replacement takes an array of source edits",
                  location: arguments.location
                )
              }
              return edit
            }
          return .sourceEdit(try value.replacement(applying: edits))
        }
        try arguments.requireLabels([.with], for: name)
        if case let .member(literal) = try arguments.value(at: 0),
           literal.owners.contains(.sourceWhitespace),
           let whitespace = SourceWhitespace(rawValue: literal.rawValue)
        {
          return .sourceEdit(try value.replacement(with: whitespace))
        }
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

  func correctionCheck(
    selection: RuntimeSelection,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    guard arguments.hasLabels([nil, nil])
      || arguments
      .hasLabels([nil, .changes])
    else {
      throw RuntimeError(
        message: "violations takes a requirement and one correction closure",
        location: arguments.location
      )
    }
    let requirement = try arguments.string(at: 0)
    let body = try arguments.value(at: 1)
    var offenders: [RuntimeModelValue] = []
    var fixes: [SourceFix?] = []
    var candidates: [SourceFix.Edit] = []
    for element in selection.elements {
      try step(at: arguments.location, state: &state)
      if let offender = element.offender,
         excludedSubtrees?
           .contains(offender.affectedPath ?? offender.location.filePath) == true
      {
        continue
      }
      let proposedEdits = try await correctionEdits(
        body, input: .model(element), method: .violations,
        at: arguments.location, state: &state
      )
      var edits: [SourceFix.Edit] = []
      for edit in proposedEdits {
        if edit.source.text.utf8.elementsEqual(edit.replacement.utf8) {
          if edit.layout != nil { candidates.append(edit) }
        } else {
          edits.append(edit)
        }
      }
      if !edits.isEmpty {
        offenders.append(element)
        fixes.append(SourceFix(edits: edits))
      }
    }
    return .violations(
      RuntimeViolations(
        rule: requirement, offenders: offenders,
        checkedCount: selection.elements.count,
        fixes: fixes, codebase: selection.codebase,
        layoutCandidates: candidates
      )
    )
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
    let title: String? =
      if count == 1 {
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
      let context = RuntimeValue.fixContext(
        RuntimeFixContext(
          offender: offender,
          codebase: violations.codebase
        )
      )
      let edits = try await correctionEdits(
        callable, input: context, method: .withFix,
        at: arguments.location, state: &state
      )
      fixes.append(edits.isEmpty ? nil : SourceFix(title, edits: edits))
    }
    return .violations(
      RuntimeViolations(
        rule: violations.rule,
        offenders: violations.offenders,
        checkedCount: violations.checkedCount,
        witnesses: violations.witnesses,
        fixes: fixes,
        codebase: violations.codebase,
        layoutCandidates: violations.layoutCandidates
      )
    )
  }

  private func correctionEdits(
    _ callable: RuntimeValue,
    input: RuntimeValue,
    method: SupportedAPI.Method,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> [SourceFix.Edit] {
    let result: RuntimeValue =
      switch callable {
      case let .closure(closure):
        try await invoke(
          closure, arguments: [input], builder: .edits, state: &state
        )
      case let .function(function):
        try await invoke(
          callable,
          arguments: [(
            function.definition.parameters.first?.externalName,
            input
          )],
          trailingClosure: nil,
          at: location,
          state: &state
        )
      default:
        throw RuntimeError(
          message: method == .withFix
            ? "withFix takes a fix closure or function"
            : "Correction takes a closure or function",
          location: location
        )
      }
    guard case let .array(values) = result else {
      throw RuntimeError(
        message: method == .withFix
          ? "withFix must return an edit array"
          : RuntimeBuilder.edits.argumentRequirement,
        location: location
      )
    }
    return try values.map { value throws(RuntimeError) -> SourceFix.Edit in
      guard case let .sourceEdit(edit) = value else {
        throw RuntimeError(
          message: method == .withFix
            ? "withFix takes SourceFix.Edit values or edit arrays"
            : RuntimeBuilder.edits.argumentRequirement,
          location: location
        )
      }
      return edit
    }
  }
}
