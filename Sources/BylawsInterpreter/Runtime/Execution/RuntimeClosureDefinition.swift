import BylawsCore
import BylawsSemantics

struct RuntimeClosureDefinition: Sendable {
  let parameters: [String]
  let body: RuntimeBody
  let location: DeclarationLocation
  let usesAwait: Bool
  let usesTry: Bool
}
