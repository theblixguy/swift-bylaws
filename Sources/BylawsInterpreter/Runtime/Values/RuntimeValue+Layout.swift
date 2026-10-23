import BylawsSemantics

extension RuntimeValue {
  func layoutOperations(at location: DeclarationLocation) throws(RuntimeError)
    -> [RuntimeLayoutOperation]
  {
    switch self {
    case let .layoutPlan(operations): return operations
    case let .layoutGroup(predicate, comparison): return [.group(
        predicate: predicate,
        comparison: comparison
      )]
    case let .sourceLayout(layout):
      return try layout.node.listOperations(at: location)
    default:
      throw RuntimeError(
        message: "SourceListLayout must contain groups and separators. Use a separate replacement for explicit source.",
        location: location
      )
    }
  }

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

extension SourceLayout.Node {
  fileprivate func listOperations(at location: DeclarationLocation)
    throws(RuntimeError) -> [RuntimeLayoutOperation]
  {
    switch self {
    case .blankLine: return [.separator(.blankLine)]
    case .newline: return [.separator(.newline)]
    case let .sequence(nodes):
      var operations: [RuntimeLayoutOperation] = []
      for node in nodes {
        operations.append(contentsOf: try node.listOperations(at: location))
      }
      return operations
    default:
      throw RuntimeError(
        message: "SourceListLayout must contain groups and separators. Use a separate replacement for explicit source.",
        location: location
      )
    }
  }
}
