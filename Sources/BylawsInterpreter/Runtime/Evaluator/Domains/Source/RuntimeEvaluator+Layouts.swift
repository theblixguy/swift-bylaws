import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func constructLayout(
    _ constructor: SupportedAPI.Constructor,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if constructor == .group {
      try arguments.requireLabels(["where"], for: constructor.rawValue)
      return .layoutGroup(
        predicate: try arguments.value(at: 0),
        comparison: nil
      )
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
    let hasWidth = arguments.hasLabels([.whenLineExceeds, nil])
    try arguments.requireLabels(
      hasWidth ? [.whenLineExceeds, nil] : [nil], for: .replacement
    )
    let maximumWidth: Int? = if hasWidth {
      switch try arguments.value(at: 0) {
      case let .integer(value), let .optional(.integer(value)):
        value
      case .optional(nil): nil
      default:
        throw RuntimeError(
          message: "SourceLayout width must be Int or nil",
          location: arguments.location
        )
      }
    } else {
      nil
    }
    let result = try await layoutResult(
      arguments.value(at: arguments.values.count - 1),
      at: arguments.location,
      state: &state
    )
    do {
      let providers =
        try elements
          .map { try $0.sourceProvider(at: arguments.location) }
      if case let .layoutPlan(plan) = result {
        guard !hasWidth else {
          throw RuntimeError(
            message: "SourceListLayout must use an unconditional replacement. Remove whenLineExceeds.",
            location: arguments.location
          )
        }
        let operations = try await resolveLayoutPlan(
          plan, elements: elements, at: arguments.location, state: &state
        )
        return .sourceFix(try SourceListLayoutReplacement.make(
          elements: providers, operations: operations
        ))
      }
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
          whenLineExceeds: maximumWidth
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
    let result = try await layoutResult(callable, at: location, state: &state)
    guard case let .sourceLayout(layout) = result else {
      throw RuntimeError(
        message: "SourceLayout must emit source values. Use groups in a collection replacement.",
        location: location
      )
    }
    return layout
  }

  private func layoutResult(
    _ callable: RuntimeValue,
    at location: DeclarationLocation,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
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
    switch result {
    case .sourceLayout:
      if case let .closure(closure) = callable,
         closure.definition.isAutomaticLayout
      {
        return .layoutPlan(try result.layoutOperations(at: location))
      }
      return result
    case .layoutPlan: return result
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
