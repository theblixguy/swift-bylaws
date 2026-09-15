import BylawsCore
import BylawsSemantics
import Foundation
import SwiftSyntax

extension RuntimeEvaluator {
  func modelMethod(
    _ name: SupportedAPI.Method,
    value: RuntimeModelValue,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if case let .packageManifest(manifest) = value {
      return try manifestMethod(name, manifest: manifest, arguments: arguments)
    }
    switch (name, value) {
    case let (.contains, .compilationBranch(branch)):
      try arguments.requireLabels([nil], for: name)
      guard case let .model(.check(.location(location))) = try arguments
        .value(at: 0)
      else {
        throw RuntimeError(
          message: "CompilationBranch.contains takes one DeclarationLocation",
          location: arguments.location
        )
      }
      return .boolean(branch.contains(location))
    case let (.directTargetDependencies, .bazelGraph(graph)),
         let (.transitiveTargetDependencies, .bazelGraph(graph)):
      return try bazelDependencies(name, graph: graph, arguments: arguments)
    case let (.withSyntax, .sourceFile(file)):
      if arguments.values.count == 1 {
        try arguments.requireLabels([nil], for: name)
        return try await invokeSynchronous(
          arguments.closure(at: 0),
          arguments: [.model(.syntaxSourceFile(file.withSyntax { $0 }))],
          kind: "withSyntax",
          state: &state
        )
      }
      try arguments.requireLabels([.of, .as, nil], for: name)
      guard case let .model(declaration) = try arguments.value(at: 0),
            case let .genericType(type, _) = try arguments.value(at: 1),
            type == SupportedAPI.ModelType.syntaxClass.rawValue,
            case let .classDeclaration(classDeclaration) = declaration,
            let node = file.withSyntax(
              of: classDeclaration,
              as: ClassDeclSyntax.self,
              { $0 }
            )
      else {
        return .optional(nil)
      }
      return .optional(
        try await invokeSynchronous(
          arguments.closure(at: 2),
          arguments: [.model(.syntaxClass(node))],
          kind: "withSyntax",
          state: &state
        )
      )
    case let (.tokens, .syntaxSourceFile(file)):
      try arguments.requireLabels([.viewMode], for: name)
      guard case let .member(mode) = try arguments.value(at: 0),
            mode == .constant(.sourceAccurate)
      else {
        throw RuntimeError(
          message: "tokens(viewMode:) supports '.sourceAccurate'",
          location: arguments.location
        )
      }
      return .array(
        file.tokens(viewMode: .sourceAccurate).map {
          .model(.syntaxToken($0))
        }
      )
    case let (.imports, .sourceFile(value)):
      try arguments.requireLabels([nil], for: name)
      return .boolean(value.imports(try arguments.string(at: 0)))
    case let (.calls, .sourceFile(value)):
      try arguments.requireLabels([nil], for: name)
      return .boolean(value.calls(try arguments.string(at: 0)))
    case let (.calls, .function(value)):
      try arguments.requireLabels([nil], for: name)
      return .boolean(value.calls(try arguments.string(at: 0)))
    case let (.calls, .property(value)):
      try arguments.requireLabels([nil], for: name)
      return .boolean(value.calls(try arguments.string(at: 0)))
    case let (.references, .functionCall(value)):
      try arguments.requireLabels([nil], for: name)
      return .boolean(value.references(try arguments.string(at: 0)))
    case let (.hasArgumentLabel, .functionCall(value)):
      try arguments.requireLabels([nil], for: name)
      return .boolean(value.hasArgumentLabel(try arguments.string(at: 0)))
    case let (.references, .typeReference(value)):
      try arguments.requireLabels([nil], for: name)
      return .boolean(value.references(try arguments.string(at: 0)))
    case (.hasAttribute, _):
      try arguments.requireLabels([nil], for: name)
      let wanted = try arguments.string(at: 0)
      return .boolean(value.attributes?.contains { $0.name == wanted } == true)
    case (.attribute, _):
      try arguments.requireLabels([.named], for: name)
      let wanted = try arguments.string(at: 0)
      return .optional(
        value.attributes?.first { $0.name == wanted }
          .map { .model(.attribute($0)) }
      )
    case (.inherits, _), (.directlyInherits, _), (.conforms, _),
         (.directlyConforms, _):
      let label: SupportedAPI.ArgumentLabel =
        switch name {
        case .conforms, .directlyConforms: .to
        default: .from
        }
      try arguments.requireLabels(
        [label],
        for: name
      )
      let wanted = try arguments.string(at: 0)
      guard let inherited = value.inheritedTypes,
            let allInherited = value.allInheritedTypes
      else {
        throw RuntimeError(
          message: "'\(name.rawValue)' does not apply to this value",
          location: arguments.location
        )
      }
      let direct = inherited.contains { $0.withoutTypeAttributes == wanted }
      let any = allInherited.contains { $0.withoutTypeAttributes == wanted }
      return .boolean(
        name == .directlyInherits || name == .directlyConforms ? direct : any
      )
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported method of this model value",
        location: arguments.location
      )
    }
  }
}

extension RuntimeValue {
  func matcher(at location: DeclarationLocation) throws(RuntimeError)
    -> RuntimeMatcher
  {
    guard case let .matcher(value) = self else {
      throw RuntimeError(
        message: "this value is not a Matcher",
        location: location
      )
    }
    return value
  }
}

extension RuntimeModelValue {
  private var declaration: (any Named)? {
    if case let .enumCase(value) = self { return value }
    return matcherSubject
  }

  var name: String? {
    switch self {
    case let .parameter(value): value.name
    case let .attribute(value): value.name
    case let .genericParameter(value): value.name
    case let .importGraphTarget(value): value.name
    case let .manifest(value): value.name
    case let .indexReference(value): value.symbol.name
    case let .indexSymbol(value): value.name
    case let .offender(value): value.name
    default: declaration?.name
    }
  }

  var filePath: String? {
    offender?.location.filePath
  }

  var attributes: [Attribute]? {
    (declaration as? any Attributed)?.attributes
  }

  var inheritedTypes: [String]? {
    if case let .extensionDeclaration(value) = self {
      return value.inheritedTypes
    }
    return (declaration as? any InheritanceProviding)?.inheritedTypes
  }

  var allInheritedTypes: [String]? {
    if case let .extensionDeclaration(value) = self {
      return value.allInheritedTypes
    }
    return (declaration as? any InheritanceProviding)?.allInheritedTypes
  }
}
