import BylawsCore
import BylawsSemantics

extension RuntimeModelValue {
  var source: SourceSlice {
    get throws {
      switch self {
      case let .sourceFile(value): try value.source
      case let .classDeclaration(value): try value.source
      case let .actor(value): try value.source
      case let .structDeclaration(value): try value.source
      case let .enumDeclaration(value): try value.source
      case let .nominalType(value): try value.source
      case let .protocolDeclaration(value): try value.source
      case let .extensionDeclaration(value): try value.source
      case let .function(value): try value.source
      case let .property(value): try value.source
      case let .initializer(value): try value.source
      case let .importDeclaration(value): try value.source
      case let .typealiasDeclaration(value): try value.source
      case let .functionCall(value): try value.source
      case let .sourceNode(value): try value.source
      case let .sourceExpression(value): try value.source
      case let .sourceAssignment(value): try value.source
      case let .enumCase(value): try value.source
      case let .callArgument(value): try value.source
      case let .expressionArgument(value): try value.source
      case let .variableBinding(value): try value.source
      default:
        throw RuntimeError(
          message: "this value has no editable source. Select a parsed source value.",
          location: offender?.location ?? .start(of: "<interpreted rule>")
        )
      }
    }
  }
}
