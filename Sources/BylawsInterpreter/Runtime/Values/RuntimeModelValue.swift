import BylawsCore
import BylawsSemantics
import SwiftSyntax

enum RuntimeModelValue: Sendable, Equatable {
  case check(RuntimeCheckValue)
  case sourceFile(SourceFile)
  case classDeclaration(Class)
  case actor(Actor)
  case structDeclaration(Struct)
  case enumDeclaration(Enum)
  case nominalType(NominalType)
  case protocolDeclaration(ProtocolDeclaration)
  case extensionDeclaration(Extension)
  case function(Function)
  case property(Property)
  case initializer(Initializer)
  case importDeclaration(Import)
  case typealiasDeclaration(Typealias)
  case functionCall(FunctionCall)
  case typeReference(TypeReference)
  case parameter(Parameter)
  case attribute(Attribute)
  case genericParameter(GenericParameter)
  case enumCase(EnumCase)
  case importGraph(ImportGraph)
  case importGraphTarget(ImportGraph.Target)
  case packageManifest(PackageManifest)
  case manifest(RuntimeManifestValue)
  case indexReference(RuntimeIndexReference)
  case indexSymbol(RuntimeIndexSymbol)
  case offender(Offender)
  case syntaxClass(ClassDeclSyntax)
  case syntaxMemberBlock(MemberBlockSyntax)
  case syntaxSourceFile(SourceFileSyntax)
  case syntaxToken(TokenSyntax)
  case syntaxTriviaPiece(TriviaPiece)

  var offender: Offender? {
    switch self {
    case let .sourceFile(value): runtimeOffender(value)
    case let .classDeclaration(value): runtimeOffender(value)
    case let .actor(value): runtimeOffender(value)
    case let .structDeclaration(value): runtimeOffender(value)
    case let .enumDeclaration(value): runtimeOffender(value)
    case let .nominalType(value): runtimeOffender(value)
    case let .protocolDeclaration(value): runtimeOffender(value)
    case let .extensionDeclaration(value): runtimeOffender(value)
    case let .function(value): runtimeOffender(value)
    case let .property(value): runtimeOffender(value)
    case let .initializer(value): runtimeOffender(value)
    case let .importDeclaration(value): runtimeOffender(value)
    case let .typealiasDeclaration(value): runtimeOffender(value)
    case let .functionCall(value): runtimeOffender(value)
    case .check, .typeReference, .parameter, .attribute, .genericParameter,
         .importGraph, .importGraphTarget, .packageManifest, .manifest,
         .indexSymbol, .syntaxClass,
         .syntaxMemberBlock, .syntaxSourceFile, .syntaxToken,
         .syntaxTriviaPiece:
      nil
    case let .enumCase(value): runtimeOffender(value)
    case let .indexReference(value): value.offender
    case let .offender(value): value
    }
  }
}

extension RuntimeModelValue {
  var modelType: SupportedAPI.ModelType {
    switch self {
    case let .check(value): value.modelType
    case .sourceFile: .sourceFile
    case .classDeclaration: .classDeclaration
    case .actor: .actor
    case .structDeclaration: .structDeclaration
    case .enumDeclaration: .enumDeclaration
    case .nominalType: .nominalType
    case .protocolDeclaration: .protocolDeclaration
    case .extensionDeclaration: .extensionDeclaration
    case .function: .function
    case .property: .property
    case .initializer: .initializer
    case .importDeclaration: .importDeclaration
    case .typealiasDeclaration: .typealiasDeclaration
    case .functionCall: .functionCall
    case .typeReference: .typeReference
    case .parameter: .parameter
    case .attribute: .attribute
    case .genericParameter: .genericParameter
    case .enumCase: .enumCase
    case .importGraph: .importGraph
    case .importGraphTarget: .importGraphTarget
    case .packageManifest: .packageManifest
    case let .manifest(value): value.modelType
    case .indexReference: .indexReference
    case .indexSymbol: .indexSymbol
    case .offender: .offender
    case .syntaxClass: .syntaxClass
    case .syntaxMemberBlock: .syntaxMemberBlock
    case .syntaxSourceFile: .syntaxSourceFile
    case .syntaxToken: .syntaxToken
    case .syntaxTriviaPiece: .syntaxTriviaPiece
    }
  }
}

private func runtimeOffender(_ value: some Located) -> Offender {
  Offender(
    description: (value as? any Summarised)?.summary
      ?? String(describing: value),
    name: (value as? any Named)?.name,
    location: value.location
  )
}
