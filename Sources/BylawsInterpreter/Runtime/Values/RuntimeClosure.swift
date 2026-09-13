struct RuntimeClosure: Sendable {
  let definition: RuntimeClosureDefinition
  let captures: RuntimeEnvironment
}
