import BylawsSemantics

extension RuntimeEvaluator {
  func assignmentMember(
    _ name: SupportedAPI.Member, _ value: SourceAssignment
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .target: .model(.sourceExpression(value.target))
    case .value: .model(.sourceExpression(value.value))
    case .operatorName: .string(value.operatorName)
    case .compilationBranches: modelArray(
        value.compilationBranches,
        RuntimeModelValue.compilationBranch
      )
    case .enclosingDeclarations:
      modelArray(
        value.enclosingDeclarations,
        RuntimeModelValue.enclosingDeclaration
      )
    default: nil
    }
  }

  func variableBindingMember(
    _ name: SupportedAPI.Member, _ value: VariableBinding
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .initialValue: optionalModel(
        value.initialValue,
        RuntimeModelValue.sourceExpression
      )
    case .isMutable: .boolean(value.isMutable)
    case .compilationBranches: modelArray(
        value.compilationBranches,
        RuntimeModelValue.compilationBranch
      )
    case .enclosingDeclarations:
      modelArray(
        value.enclosingDeclarations,
        RuntimeModelValue.enclosingDeclaration
      )
    default: nil
    }
  }
}
