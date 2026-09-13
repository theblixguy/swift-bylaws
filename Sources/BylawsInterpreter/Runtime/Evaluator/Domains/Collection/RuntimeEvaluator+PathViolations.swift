import BylawsCore

extension RuntimeEvaluator {
  func pathViolations(
    in selection: RuntimeSelection,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    try arguments.requireLabels([.outsidePaths], for: .violations)
    let patterns = if case let .string(pattern) = try arguments.value(at: 0) {
      [pattern]
    } else {
      try arguments.strings(at: 0)
    }
    guard let rootPath = selection.rootPath else {
      throw RuntimeError(
        message: "Path checks must use a selection from a codebase.",
        location: arguments.location
      )
    }
    let matcher = Matcher<Offender>.pathRequirement(
      patterns,
      relativeTo: rootPath
    )
    return .violations(RuntimeViolations(
      rule: matcher.requirementDescription,
      offenders: selection.elements.filter { value in
        value.offender.map { !matcher($0) } == true
      },
      checkedCount: selection.elements.count
    ))
  }
}
