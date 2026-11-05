import BylawsSemantics

extension RuntimeValue {
  func layoutOperations(at location: DeclarationLocation) throws(RuntimeError)
    -> [RuntimeLayoutOperation]
  {
    switch self {
    case let .layoutPlan(operations): operations
    case let .layoutGroup(group): [.group(group)]
    default:
      [.layout(SourceLayout(node: try layoutNode(at: location)))]
    }
  }

  func layoutNode(at location: DeclarationLocation) throws(RuntimeError)
    -> SourceLayout.Node
  {
    switch self {
    case let .layoutPlan(operations):
      let nodes = try operations
        .map { operation throws(RuntimeError) -> SourceLayout.Node in
          switch operation {
          case let .separator(whitespace):
            whitespace == .blankLine ? .blankLine : .newline
          default: throw RuntimeError(
              message: RuntimeBuilder.sourceLayout.argumentRequirement,
              location: location
            )
          }
        }
      return .sequence(nodes)
    case let .sourceLayout(layout): return layout.node
    case .member(.constant(.newline)): return .newline
    case .member(.constant(.blankLine)): return .blankLine
    case .member(.constant(.softBreak)): return .softBreak
    case let .sourceCorrection(correction),
         let .layoutCorrection(correction): return SourceLayout(correction)
      .node
    case let .sourceFix(fix): return SourceLayout(fix).node
    case let .sourceSlice(source): return .source(source)
    case let .sourceEdit(edit): return .edit(edit)
    case let .model(model) where SupportedAPI.sourceProvidingModels
      .contains(model.modelType):
      return .source(try model.sourceProvider)
    default:
      if let values = sequenceElements {
        return .sequence(try values.map { value throws(RuntimeError) in
          try value.layoutNode(at: location)
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
    case let .sourceList(list): return list.source
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
