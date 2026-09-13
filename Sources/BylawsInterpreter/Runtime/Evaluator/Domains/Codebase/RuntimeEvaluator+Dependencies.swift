import BylawsCore

extension RuntimeEvaluator {
  func dependencyCheck(
    _ method: SupportedAPI.Method,
    codebase: Codebase,
    arguments: RuntimeArguments
  ) async throws(RuntimeError) -> RuntimeValue {
    let index = try projectIndex(
      over: codebase,
      arguments,
      declaredBy: try indexQueryCall(
        method,
        on: .codebase,
        at: arguments.location
      )
    )
    let provider = try requireIndexProvider(at: arguments.location)
    if method == .checkDependencyCycles {
      let groups = try arguments.array(at: 0)
        .map { value throws(RuntimeError) in
          guard case let .dependencyGroup(group) = value else {
            throw RuntimeError(
              message: "checkDependencyCycles takes an array of DependencyGroup values",
              location: arguments.location
            )
          }
          return group
        }
      let findings = try await reportingFailures(at: arguments.location) {
        try await provider.checkDependencyCycles(
          between: groups,
          in: index,
          location: arguments.location
        )
      }
      return .findings(findings)
    }
    var folderPattern: String?
    for position in arguments.values.indices.dropFirst(2)
      where arguments.label(at: position) == .allowingWithinFoldersMatching
    {
      switch try arguments.value(at: position) {
      case .optional(nil): folderPattern = nil
      case let .string(value), let .optional(.some(.string(value))):
        folderPattern = value
      default:
        throw RuntimeError(
          message: "allowingWithinFoldersMatching must be String or nil",
          location: arguments.location
        )
      }
    }
    let findings = try await reportingFailures(at: arguments.location) {
      try await provider.checkDependencies(
        from: arguments.strings(at: 0),
        allowingReferencesTo: arguments.strings(at: 1),
        allowingWithinFoldersMatching: folderPattern,
        in: index,
        location: arguments.location
      )
    }
    return .findings(findings)
  }
}
