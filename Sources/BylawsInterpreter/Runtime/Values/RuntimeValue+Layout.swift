import BylawsSemantics

extension RuntimeValue {
  func layoutNode(at location: DeclarationLocation) throws(RuntimeError)
    -> SourceLayout.Node
  {
    switch self {
    case let .sourceLayout(layout): return layout.node
    case let .sourceSlice(source): return .source(source)
    case let .sourceEdit(edit): return .edit(edit)
    case let .model(model) where SupportedAPI.sourceProvidingModels
      .contains(model.modelType):
      return .source(try model.sourceProvider)
    default:
      if let values = sequenceElements {
        return .sequence(try values
          .map { value throws(RuntimeError) -> SourceLayout.Node in
            .source(try value.sourceProvider(at: location))
          })
      }
      throw RuntimeError(
        message: RuntimeBuilder.layout.argumentRequirement,
        location: location
      )
    }
  }

  func sourceProvider(at location: DeclarationLocation) throws(RuntimeError)
    -> any SourceProviding
  {
    switch self {
    case let .sourceSlice(source): return source
    case let .model(model) where SupportedAPI.sourceProvidingModels
      .contains(model.modelType):
      return try model.sourceProvider
    default:
      throw RuntimeError(
        message: "SourceLayout must contain captured source. Select a parsed source value.",
        location: location
      )
    }
  }
}
