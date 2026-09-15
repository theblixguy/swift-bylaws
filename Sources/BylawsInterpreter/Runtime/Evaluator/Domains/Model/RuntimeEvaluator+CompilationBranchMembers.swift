import BylawsSemantics

extension RuntimeEvaluator {
  func compilationBranchMember(
    _ name: SupportedAPI.Member, _ value: CompilationBranch
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .condition: optionalString(value.condition)
    case .precedingConditions: .array(value.precedingConditions
        .map(RuntimeValue.string))
    default: nil
    }
  }
}
