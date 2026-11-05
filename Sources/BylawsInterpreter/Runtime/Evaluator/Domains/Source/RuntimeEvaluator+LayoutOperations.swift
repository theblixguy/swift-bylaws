import BylawsSemantics

extension RuntimeEvaluator {
  func constructLayoutOperation(
    _ arguments: RuntimeArguments, state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    let stored = arguments.hasLabels([nil, .layout])
      || arguments.hasLabels([nil, .layout, .when])
    let hasCondition = arguments.values.contains { $0.label == "when" }
    let condition = try hasCondition ? layoutCondition(
      in: arguments,
      at: stored ? 2 : 1
    ) : nil
    let values = try arguments.value(at: 0)
    guard let elements = values.sequenceElements else {
      throw RuntimeError(
        message: "Layout takes a collection of captured source",
        location: arguments.location
      )
    }
    let content = try arguments
      .value(at: stored ? 1 : arguments.values.count - 1)
    let result = if stored {
      try RuntimeBuilder.layout.combine([content], at: arguments.location)
    } else {
      try await layoutResult(content, at: arguments.location, state: &state)
    }
    do {
      let providers = try elements.map { value throws(RuntimeError) in
        try value.sourceProvider(at: arguments.location)
      }
      let layout: SourceLayout
      if case let .layoutPlan(plan) = result {
        let explicit = plan.compactMap { operation -> SourceLayout? in
          if case let .layout(layout) = operation { layout } else { nil }
        }
        if let error = SourceLayout(node: .sequence(explicit.map(\.node)))
          .correctionError
        {
          throw error
        }
        let hasPolicies = plan.contains { operation in
          switch operation {
          case .group, .conditionalSeparator: true
          case .layout, .separator: false
          }
        }
        if hasPolicies {
          guard explicit.isEmpty
          else { throw SourceListLayoutError.mixedContent }
          let operations = try await resolveLayoutPlan(
            plan, elements: elements, at: arguments.location, state: &state
          )
          let fix = try SourceListLayoutReplacement.make(
            elements: providers, operations: operations, when: condition
          )
          return .layoutCorrection(elements
            .isEmpty ? .notApplicable : SourceCorrection(fix))
        }
        let nodes = try plan.map { operation throws -> SourceLayout.Node in
          switch operation {
          case let .layout(layout): layout.node
          case let .separator(whitespace): whitespace == .blankLine ?
            .blankLine : .newline
          case .group,
               .conditionalSeparator: throw SourceListLayoutError.mixedContent
          }
        }
        layout = SourceLayout(node: .sequence(nodes))
      } else if case let .sourceLayout(value) = result {
        layout = value
      } else {
        throw RuntimeError(
          message: RuntimeBuilder.layout.argumentRequirement,
          location: arguments.location
        )
      }
      if elements.isEmpty || layout.isEmpty {
        _ = try layout.sources
        return .layoutCorrection(.notApplicable)
      }
      let edit = try SourceLayoutReplacement.make(
        elements: providers, layout: layout, when: condition
      )
      return .layoutCorrection(SourceCorrection(edits: [edit]))
    } catch let error as SourceCorrectionError {
      let correction: SourceCorrection = switch error {
      case let .unavailable(reason): .unavailable(reason)
      case let .undetermined(reason): .undetermined(reason)
      }
      return .layoutCorrection(correction)
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }
}
