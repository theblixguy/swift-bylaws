import BylawsCore
import BylawsSemantics

extension RuntimeModelValue {
  var source: SourceSlice {
    get throws { try sourceProvider.source }
  }

  var sourceProvider: any SourceProviding {
    get throws(RuntimeError) {
      switch self {
      case let .sourceFile(value): value
      case let .classDeclaration(value): value
      case let .actor(value): value
      case let .structDeclaration(value): value
      case let .enumDeclaration(value): value
      case let .nominalType(value): value
      case let .protocolDeclaration(value): value
      case let .extensionDeclaration(value): value
      case let .function(value): value
      case let .property(value): value
      case let .initializer(value): value
      case let .importDeclaration(value): value
      case let .typealiasDeclaration(value): value
      case let .functionCall(value): value
      case let .sourceToken(value): value
      case let .sourceTrivia(value): value
      case let .sourceNode(value): value
      case let .sourceExpression(value): value
      case let .sourceAssignment(value): value
      case let .enumCase(value): value
      case let .callArgument(value): value
      case let .expressionArgument(value): value
      case let .variableBinding(value): value
      case let .attribute(value): value
      case let .dictionaryElement(value): value
      default:
        throw RuntimeError(
          message: "this value has no editable source. Select a parsed source value.",
          location: offender?.location ?? .start(of: "<interpreted rule>")
        )
      }
    }
  }
}
