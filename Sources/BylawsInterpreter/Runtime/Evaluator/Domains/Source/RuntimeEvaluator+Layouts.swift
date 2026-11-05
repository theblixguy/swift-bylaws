import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func constructLayout(
    _ constructor: SupportedAPI.Constructor,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if constructor == .layout {
      return try await constructLayoutOperation(arguments, state: &state)
    }
    if constructor == .group {
      let projected = arguments.hasLabels([nil, .where])
        || arguments.hasLabels([nil, nil])
      return .layoutGroup(RuntimeLayoutGroup(
        projection: projected ? try arguments.value(at: 0) : nil,
        predicate: try arguments.value(at: projected ? 1 : 0)
      ))
    }
    if constructor == .newline || constructor == .blankLine || constructor ==
      .softBreak
    {
      if constructor != .softBreak, !arguments.values.isEmpty {
        return try conditionalSeparator(constructor, arguments: arguments)
      }
      try arguments.requireLabels([], for: constructor.rawValue)
      let node: SourceLayout.Node =
        switch constructor {
        case .newline: .newline
        case .blankLine: .blankLine
        default: .softBreak
        }
      if constructor != .softBreak {
        return .layoutPlan([.separator(constructor == .blankLine ? .blankLine :
            .newline)])
      }
      return .sourceLayout(SourceLayout(node: node))
    }
    let values = arguments.values
    let bodyIndex = values[0].label == "width" || values[0]
      .label == "boundaries" ? 1 : 0
    let value = try arguments.value(at: bodyIndex)
    let layout: SourceLayout = switch value {
    case .closure, .function:
      try await layoutBody(value, at: arguments.location, state: &state)
    default:
      try SourceLayout(node: value.layoutNode(at: arguments.location))
    }
    let node: SourceLayout.Node
    switch constructor {
    case .sourceLayout: node = layout.node
    case .line: node = .line(layout.node)
    case .lines:
      let boundaries: Lines.Boundaries
      if let argument = values.first(where: { $0.label == "boundaries" }) {
        switch argument.value {
        case .member(.constant(.newline)): boundaries = .newline
        case .member(.constant(.preserved)): boundaries = .preserved
        default: throw RuntimeError(
            message: "Lines boundaries must be .preserved or .newline",
            location: arguments.location
          )
        }
      } else { boundaries = .preserved }
      node = Lines(layout: layout, boundaries: boundaries).layout.node
    case .indent: node = .indent(layout.node)
    case .align: node = .align(layout.node)
    case .wrap:
      let width: Int?
      if let argument = values.first(where: { $0.label == "width" }) {
        switch argument.value {
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
    let stored = arguments.hasLabels([.layout]) || arguments.hasLabels([
      .layout,
      .when,
    ])
    let hasCondition = arguments.hasLabels([.when, nil]) || arguments
      .hasLabels([
        .layout,
        .when,
      ])
    try arguments.requireLabels(
      stored ? (hasCondition ? [.layout, .when] : [.layout]) : (hasCondition ? [
        .when,
        nil,
      ] : [nil]), for: .replacement
    )
    let condition = try hasCondition ? layoutCondition(
      in: arguments,
      at: stored ? 1 : 0
    ) : nil
    let result = if stored { try arguments.value(at: 0) } else {
      try await layoutResult(
        arguments.value(at: arguments.values.count - 1),
        at: arguments.location, builder: .sourceLayout,
        state: &state
      )
    }
    do {
      let providers =
        try elements
          .map { try $0.sourceProvider(at: arguments.location) }
      guard case let .sourceLayout(layout) = result else {
        throw RuntimeError(
          message: RuntimeBuilder.layout.argumentRequirement,
          location: arguments.location
        )
      }
      return .sourceEdit(
        try SourceLayoutReplacement.make(
          elements: providers,
          layout: layout,
          when: condition
        )
      )
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }

  func layoutBody(
    _ callable: RuntimeValue,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> SourceLayout {
    let result = try await layoutResult(
      callable,
      at: location,
      builder: .sourceLayout,
      state: &state
    )
    guard case let .sourceLayout(layout) = result else {
      throw RuntimeError(
        message: "SourceLayout must emit source values. Use groups in Layout.",
        location: location
      )
    }
    return layout
  }

  func layoutResult(
    _ callable: RuntimeValue,
    at location: DeclarationLocation, builder: RuntimeBuilder = .layout,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let result: RuntimeValue
    switch callable {
    case let .closure(closure):
      result = try await invokeSynchronous(
        closure, arguments: [], kind: "layout", allowsThrowing: true,
        builder: builder, state: &state
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
    switch result {
    case let .sourceLayout(layout):
      if layout.correctionError != nil { return result }
      return result
    case .layoutPlan: return result
    case .layoutGroup where builder == .layout:
      return try builder.combine([result], at: location)
    default:
      throw RuntimeError(
        message: RuntimeBuilder.layout.argumentRequirement,
        location: location
      )
    }
  }

  private func conditionalSeparator(
    _ constructor: SupportedAPI.Constructor,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    let condition: RuntimeLayoutOperation.Condition
    if arguments.hasLabels([.before]) {
      condition = .before(try arguments.value(at: 0))
    } else if arguments.hasLabels([.after]) {
      condition = .after(try arguments.value(at: 0))
    } else if arguments.hasLabels([.between, .and]) {
      condition = .between(
        try arguments.value(at: 0),
        try arguments.value(at: 1)
      )
    } else {
      throw RuntimeError(
        message: "\(constructor.rawValue) takes one predicate with before: or after:, or two predicates with between:and:",
        location: arguments.location
      )
    }
    return .layoutPlan([.conditionalSeparator(
      condition, constructor == .blankLine ? .blankLine : .newline
    )])
  }
}
