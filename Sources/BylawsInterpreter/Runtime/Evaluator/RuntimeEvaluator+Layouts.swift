import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func constructLayout(
    _ constructor: SupportedAPI.Constructor,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if constructor == .newline || constructor == .blankLine || constructor ==
      .softBreak
    {
      try arguments.requireLabels([], for: constructor.rawValue)
      let node: SourceLayout.Node =
        switch constructor {
        case .newline: .newline
        case .blankLine: .blankLine
        default: .softBreak
        }
      return .sourceLayout(SourceLayout(node: node))
    }
    let values = arguments.values
    let takesWidth = constructor == .wrap && values.count == 2
    try arguments.requireLabels(
      takesWidth ? ["width", nil] : [nil],
      for: constructor.rawValue
    )
    let layout = try await layoutBody(
      arguments.value(at: values.count - 1),
      at: arguments.location,
      state: &state
    )
    let node: SourceLayout.Node
    switch constructor {
    case .sourceLayout: node = layout.node
    case .line: node = .line(layout.node)
    case .indent: node = .indent(layout.node)
    case .align: node = .align(layout.node)
    case .wrap:
      let width: Int?
      if takesWidth {
        switch try arguments.value(at: 0) {
        case let .integer(value), let .optional(.integer(value)): width = value
        case .optional(nil): width = nil
        default:
          throw RuntimeError(
            message: "Wrap width must be Int or nil",
            location: arguments.location
          )
        }
      } else {
        width = nil
      }
      node = .wrap(width: width, layout.node)
    default:
      throw RuntimeError(
        message: "SourceLayout must use a layout operation",
        location: arguments.location
      )
    }
    return .sourceLayout(SourceLayout(node: node))
  }

  func layoutReplacement(
    elements: [RuntimeValue],
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    try arguments.requireLabels([nil], for: .replacement)
    let layout = try await layoutBody(
      arguments.value(at: 0),
      at: arguments.location,
      state: &state
    )
    do {
      let providers =
        try elements
          .map { try $0.sourceProvider(at: arguments.location) }
      return .sourceEdit(
        try SourceLayoutReplacement.make(
          elements: providers,
          layout: layout
        )
      )
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }

  private func layoutBody(
    _ callable: RuntimeValue,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> SourceLayout {
    let result: RuntimeValue
    switch callable {
    case let .closure(closure):
      result = try await invokeSynchronous(
        closure, arguments: [], kind: "layout", allowsThrowing: true,
        builder: .layout, state: &state
      )
    case let .function(function):
      result = try await invokeSynchronous(
        function,
        arguments: [],
        allowsThrowing: true,
        at: location,
        state: &state
      )
    default:
      throw RuntimeError(
        message: "SourceLayout takes a closure or function",
        location: location
      )
    }
    guard case let .sourceLayout(layout) = result else {
      throw RuntimeError(
        message: RuntimeBuilder.layout.argumentRequirement,
        location: location
      )
    }
    return layout
  }
}
