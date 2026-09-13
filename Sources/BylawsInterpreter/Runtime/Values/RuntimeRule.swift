import BylawsCore
import BylawsSemantics

struct RuntimeRule: Sendable {
  let id: String
  let name: String
  let enforcement: Enforcement
  let hint: String?
  let body: RuntimeClosure
  let location: DeclarationLocation
}

extension RuntimeRule {
  func resolvingCaptures(with globals: RuntimeEnvironment) -> RuntimeRule {
    var captures = globals
    captures.overlay(body.captures)
    return RuntimeRule(
      id: id,
      name: name,
      enforcement: enforcement,
      hint: hint,
      body: RuntimeClosure(definition: body.definition, captures: captures),
      location: location
    )
  }
}
