import BylawsSemantics

extension RuntimeEvaluator {
  func ifExpressionMember(
    _ name: SupportedAPI.Member,
    _ value: SourceIfExpression
  )
    -> RuntimeValue?
  {
    switch name {
    case .body: .model(.sourceNode(value.body))
    case .elseBody: optionalModel(value.elseBody, RuntimeModelValue.sourceNode)
    case .summary: .string(value.summary)
    default: nil
    }
  }

  func constructReplacement(
    _ constructor: SupportedAPI.Constructor,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    do {
      if constructor == .unwrap {
        let value = try arguments.value(at: 0)
        let target = if case let .optional(wrapped) = value { wrapped }
        else { value }
        guard let target else { return .sourceCorrection(.notApplicable) }
        let source = try target.sourceProvider(at: arguments.location).source
        return .sourceCorrection(try source.unwrapped(
          containingOnly: arguments.sourceNodeKind(at: 1)
        ))
      }
      if constructor == .replace {
        let target = try arguments.value(at: 0)
          .sourceProvider(at: arguments.location)
        let value = try arguments.value(at: 1)
        switch value {
        case let .string(text):
          return .sourceCorrection(try Replace(target, with: text).correction)
        case let .member(literal)
          where literal.owners.contains(.sourceWhitespace):
          guard let whitespace = SourceWhitespace(rawValue: literal.rawValue)
          else {
            throw RuntimeError(
              message: "Replace takes SourceWhitespace",
              location: arguments.location
            )
          }
          return .sourceCorrection(try Replace(target.source, with: whitespace)
            .correction)
        default:
          let replacement = if arguments.hasLabels([nil, .with]) {
            try value.capturedReplacement(at: arguments.location)
          } else {
            try await replacementBody(
              value,
              state: &state,
              at: arguments.location
            )
          }
          return .sourceCorrection(try Replace(target, with: replacement)
            .correction)
        }
      }
      let value = try arguments.value(at: 0)
      if arguments.hasLabels([.source]) {
        return .sourceReplacement(SourceReplacement(source: try value
            .sourceProvider(at: arguments.location)))
      }
      let replacement: SourceReplacement
      if arguments.hasLabels([.combining]) {
        guard let values = value.sequenceElements else {
          throw RuntimeError(
            message: "SourceReplacement takes a sequence of replacements",
            location: arguments.location
          )
        }
        replacement = SourceReplacement(combining: try values.map {
          value throws(RuntimeError) in try value
            .replacementContent(at: arguments.location)
        })
      } else {
        replacement = try await replacementBody(
          value,
          state: &state,
          at: arguments.location
        )
      }
      return constructor == .scope
        ? .sourceScope(Scope(replacement: replacement))
        : .sourceReplacement(replacement)
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }

  private func replacementBody(
    _ value: RuntimeValue, state: inout RuntimeEvaluationState,
    at location: DeclarationLocation
  ) async throws(RuntimeError) -> SourceReplacement {
    if case let .closure(closure) = value {
      let content = try await invokeSynchronous(
        closure, arguments: [], kind: "replacement", allowsThrowing: true,
        builder: .replacement, state: &state
      )
      return try content.replacementContent(at: location)
    }
    return try value.replacementContent(at: location)
  }

  func unwrapSource(_ value: RuntimeValue, arguments: RuntimeArguments)
    throws(RuntimeError) -> RuntimeValue
  {
    do {
      return .sourceCorrection(try value.sourceProvider(at: arguments.location)
        .source
        .unwrapped(containingOnly: arguments.sourceNodeKind(at: 0)))
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }
}

extension RuntimeArguments {
  fileprivate func sourceNodeKind(at index: Int) throws(RuntimeError)
    -> SourceNode.Kind?
  {
    guard index < values.count else { return nil }
    let value = try value(at: index)
    let kind = if case let .optional(wrapped) = value { wrapped } else { value }
    guard let kind else { return nil }
    guard case let .member(.sourceNodeKind(kind)) = kind else {
      throw RuntimeError(
        message: "Unwrap takes a SourceNode.Kind",
        location: location
      )
    }
    return kind
  }
}
