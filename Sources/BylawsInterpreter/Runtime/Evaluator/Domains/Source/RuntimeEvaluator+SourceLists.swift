import BylawsSemantics

extension RuntimeEvaluator {
  func sourceListProjection(
    _ name: SupportedAPI.Member,
    of value: RuntimeModelValue
  ) throws -> RuntimeValue? {
    switch (name, value) {
    case let (.argumentList, .functionCall(call)):
      return .sourceList(try RuntimeSourceList(call.argumentList) {
        .model(.callArgument($0))
      })
    case let (.memberList, .sourceNode(node)):
      return .sourceList(try RuntimeSourceList(node.memberList) {
        .model(.sourceNode($0))
      })
    case let (.statementList, .sourceNode(node)):
      return .sourceList(try RuntimeSourceList(node.statementList) {
        .model(.sourceNode($0))
      })
    case let (.modifierList, .sourceNode(node)):
      return .sourceList(try RuntimeSourceList(node.modifierList) {
        .model(.sourceNode($0))
      })
    default: break
    }
    if name == .attributeList,
       let declaration = try value
         .sourceProvider as? any Attributed & SourceProviding
    {
      return .sourceList(try RuntimeSourceList(declaration.attributeList) {
        .model(.attribute($0))
      })
    }
    if name == .modifierList,
       let declaration = try value
         .sourceProvider as? any Attributed & SourceProviding
    {
      return .sourceList(try RuntimeSourceList(declaration.modifierList) {
        .sourceSlice($0)
      })
    }
    return nil
  }

  func constructListCorrection(
    _ constructor: SupportedAPI.Constructor,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    do {
      switch constructor {
      case .insert:
        guard case let .sourceList(list) = try arguments.value(at: 1) else {
          throw RuntimeError(
            message: "Insert takes a SourceList", location: arguments.location
          )
        }
        let position = try arguments.values.count == 3
          ? arguments.value(at: 2).sourceListPosition(at: arguments.location)
          : .end
        return .sourceCorrection(try list.source.inserting(
          arguments.string(at: 0), at: position
        ))
      case .remove:
        return .sourceCorrection(try Remove(
          arguments.value(at: 0).sourceProvider(at: arguments.location)
        ).correction)
      default:
        preconditionFailure("Expected Insert or Remove")
      }
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }

  func sourceListMethod(
    _ name: SupportedAPI.Method,
    list: RuntimeSourceList,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    do {
      switch name {
      case .inserting:
        let position = try arguments.values.count == 2
          ? arguments.value(at: 1).sourceListPosition(at: arguments.location)
          : .end
        return .sourceCorrection(try list.source.inserting(
          arguments.string(at: 0), at: position
        ))
      case .removing:
        let source = try arguments.value(at: 0)
          .sourceProvider(at: arguments.location).source
        return .sourceCorrection(try list.source.removing(source))
      default:
        preconditionFailure("Expected inserting or removing")
      }
    } catch {
      throw RuntimeError(wrapping: error, at: arguments.location)
    }
  }
}

extension RuntimeValue {
  func sourceListPosition(
    at location: DeclarationLocation
  ) throws(RuntimeError) -> SourceListPosition {
    switch self {
    case .member(.constant(.start)): .start
    case .member(.constant(.end)): .end
    case let .sourceListPosition(position): position
    default:
      throw RuntimeError(
        message: "the position must be SourceListPosition", location: location
      )
    }
  }
}
