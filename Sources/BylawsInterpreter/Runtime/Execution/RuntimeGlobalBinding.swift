import BylawsCore
import BylawsSemantics

struct RuntimeGlobalBinding: Sendable {
  let name: String
  let type: SupportedAPI.RuntimeType?
  let expression: RuntimeExpression
  let location: DeclarationLocation
  let access: RuntimeDeclarationAccess
}
