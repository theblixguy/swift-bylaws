struct RuntimeFunction: Sendable {
  let definition: RuntimeFunctionDefinition
  let captures: RuntimeEnvironment?

  func capturing(_ environment: RuntimeEnvironment) -> RuntimeFunction {
    guard captures == nil else { return self }
    return RuntimeFunction(definition: definition, captures: environment)
  }
}
