import BylawsCore
import BylawsSemantics

struct RuntimeFunctionDefinition: Sendable {
  struct Parameter: Sendable {
    let externalName: String?
    let localName: String
    let type: SupportedAPI.RuntimeType
  }

  let name: String
  let parameters: [Parameter]
  let returnType: SupportedAPI.RuntimeType
  let isAsync: Bool
  let isThrowing: Bool
  let body: RuntimeBody
  let location: DeclarationLocation
  let access: RuntimeDeclarationAccess
}
