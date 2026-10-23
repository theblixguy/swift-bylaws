import BylawsCore
import BylawsSemantics

struct RuntimeClosureDefinition: Sendable {
  struct Parameter: Sendable {
    let name: String
    let type: SupportedAPI.RuntimeType?
  }

  let parameters: [Parameter]?
  let resultType: SupportedAPI.RuntimeType?
  let body: RuntimeBody
  let location: DeclarationLocation
  let usesAwait: Bool
  let usesTry: Bool
  let isAutomaticLayout: Bool

  init(
    parameters: [Parameter]?, body: RuntimeBody,
    location: DeclarationLocation, usesAwait: Bool, usesTry: Bool,
    resultType: SupportedAPI.RuntimeType? = nil,
    isAutomaticLayout: Bool = false
  ) {
    self.parameters = parameters
    self.resultType = resultType
    self.body = body
    self.location = location
    self.usesAwait = usesAwait
    self.usesTry = usesTry
    self.isAutomaticLayout = isAutomaticLayout
  }
}
