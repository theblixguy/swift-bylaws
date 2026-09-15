import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func codebaseMember(
    _ name: SupportedAPI.Member,
    codebase: Codebase,
    at location: DeclarationLocation
  ) async throws(RuntimeError) -> RuntimeValue {
    do {
      let root = try codebase.resolvedRootPath()
      if let value = try await codebaseMember(
        name, codebase: codebase, root: root
      ) {
        return value
      }
    } catch {
      throw RuntimeError(wrapping: error, at: location)
    }
    throw RuntimeError(
      message: "'\(name.rawValue)' is not a supported Codebase member",
      location: location
    )
  }

  private func codebaseMember(
    _ name: SupportedAPI.Member,
    codebase: Codebase,
    root: String
  ) async throws(CodebaseError) -> RuntimeValue? {
    switch name {
    case .files:
      selection(
        try await codebase.files,
        family: .file,
        root: root,
        transform: RuntimeModelValue.sourceFile
      )
    case .classes:
      selection(
        try await codebase.classes,
        family: .class,
        root: root,
        transform: RuntimeModelValue.classDeclaration
      )
    case .actors:
      selection(
        try await codebase.actors,
        family: .actor,
        root: root,
        transform: RuntimeModelValue.actor
      )
    case .structs:
      selection(
        try await codebase.structs,
        family: .struct,
        root: root,
        transform: RuntimeModelValue.structDeclaration
      )
    case .enums:
      selection(
        try await codebase.enums,
        family: .enum,
        root: root,
        transform: RuntimeModelValue.enumDeclaration
      )
    case .types:
      selection(
        try await codebase.types,
        family: .nominalType,
        root: root,
        transform: RuntimeModelValue.nominalType
      )
    case .protocols:
      selection(
        try await codebase.protocols,
        family: .protocol,
        root: root,
        transform: RuntimeModelValue.protocolDeclaration
      )
    case .extensions:
      selection(
        try await codebase.extensions,
        family: .extension,
        root: root,
        transform: RuntimeModelValue.extensionDeclaration
      )
    case .functions:
      selection(
        try await codebase.functions,
        family: .function,
        root: root,
        transform: RuntimeModelValue.function
      )
    case .properties:
      selection(
        try await codebase.properties,
        family: .property,
        root: root,
        transform: RuntimeModelValue.property
      )
    case .initializers:
      selection(
        try await codebase.initializers,
        family: .initializer,
        root: root,
        transform: RuntimeModelValue.initializer
      )
    case .imports:
      selection(
        try await codebase.imports,
        family: .import,
        root: root,
        transform: RuntimeModelValue.importDeclaration
      )
    case .typealiases:
      selection(
        try await codebase.typealiases,
        family: .typealias,
        root: root,
        transform: RuntimeModelValue.typealiasDeclaration
      )
    case .calls:
      selection(
        try await codebase.calls,
        family: .functionCall,
        root: root,
        transform: RuntimeModelValue.functionCall
      )
    case .packageManifest:
      .model(.packageManifest(try await codebase.packageManifest))
    case .expressions:
      selection(
        try await codebase.expressions, family: .sourceExpression,
        root: root, transform: RuntimeModelValue.sourceExpression
      )
    default:
      nil
    }
  }

  private func selection<Element: Sendable>(
    _ selection: Selection<Element>,
    family: SupportedAPI.DeclarationFamily,
    root: String,
    transform: (Element) -> RuntimeModelValue
  ) -> RuntimeValue {
    .selection(
      RuntimeSelection(
        family: family,
        elements: selection.map(transform),
        queryDescription: selection.queryDescription,
        rootPath: root
      )
    )
  }
}
