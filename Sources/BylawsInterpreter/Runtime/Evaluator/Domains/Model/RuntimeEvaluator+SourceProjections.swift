import BylawsSemantics

extension RuntimeEvaluator {
  func sourceProjection(
    _ name: SupportedAPI.Member,
    of value: RuntimeModelValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue? {
    do {
      if name == .source { return .sourceSlice(try value.source) }
      if name ==
        .spacing { return .sourceSpacing(try value.sourceProvider.spacing) }
      if name == .tokens {
        return .array(try value.sourceProvider.tokens
          .map { .model(.sourceToken($0)) })
      }
      if name == .trivia {
        return .array(try value.sourceProvider.trivia
          .map { .model(.sourceTrivia($0)) })
      }
      switch (name, value) {
      case let (.nameSource, .classDeclaration(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .actor(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .structDeclaration(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .enumDeclaration(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .nominalType(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .protocolDeclaration(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .function(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .property(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .initializer(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .typealiasDeclaration(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .functionCall(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .importDeclaration(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .extensionDeclaration(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .enumCase(value)):
        return .sourceSlice(try value.nameSource)
      case let (.nameSource, .variableBinding(value)):
        return .sourceSlice(try value.nameSource)
      case let (.bodySource, .classDeclaration(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .actor(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .structDeclaration(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .enumDeclaration(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .nominalType(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .protocolDeclaration(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .extensionDeclaration(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .property(value)):
        return .sourceSlice(try value.bodySource)
      case let (.bodySource, .initializer(value)):
        return .sourceSlice(try value.bodySource)
      case let (.expressionSource, .expressionArgument(value)):
        return .sourceSlice(try value.expressionSource)
      case let (.labelSource, .expressionArgument(value)):
        return .optional(try value.labelSource.map(RuntimeValue.sourceSlice))
      case let (.bodySource, .function(value)):
        return .sourceSlice(try value.bodySource)
      case let (.calledExpressionSource, .functionCall(value)):
        return .sourceSlice(try value.calledExpressionSource)
      case let (.memberNameSource, .functionCall(value)):
        return .sourceSlice(try value.memberNameSource)
      case let (.expressionSource, .callArgument(value)):
        return .sourceSlice(try value.expressionSource)
      case let (.labelSource, .callArgument(value)):
        return .optional(try value.labelSource.map(RuntimeValue.sourceSlice))
      default: return nil
      }
    } catch {
      throw RuntimeError(wrapping: error, at: location)
    }
  }
}
