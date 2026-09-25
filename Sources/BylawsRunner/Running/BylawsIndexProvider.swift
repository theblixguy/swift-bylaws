import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsInterpreter
import BylawsSemantics

struct BylawsIndexProvider: RuntimeIndexProvider {
  func checkDependencies(
    from sourcePatterns: [String],
    allowingReferencesTo destinationPatterns: [String],
    allowingWithinFoldersMatching folderPattern: String?,
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async throws(RuntimeIndexError) -> Rule.Findings {
    do {
      return try await index.codebase.checkDependencies(
        from: sourcePatterns,
        allowingReferencesTo: destinationPatterns,
        allowingWithinFoldersMatching: folderPattern,
        modules: index.modules,
        unitOutputFiles: index.unitOutputFiles,
        location: location
      )
    } catch {
      throw RuntimeIndexError(error)
    }
  }

  func checkDependencyCycles(
    between groups: [DependencyGroup],
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async throws(RuntimeIndexError) -> Rule.Findings {
    do {
      return try await index.codebase.checkDependencyCycles(
        between: groups,
        modules: index.modules,
        unitOutputFiles: index.unitOutputFiles,
        location: location
      )
    } catch {
      throw RuntimeIndexError(error)
    }
  }

  func indexedFindings(
    of layering: Layering,
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async throws(RuntimeIndexError) -> Rule.Findings {
    do {
      return try await index.codebase.indexedFindings(
        of: layering,
        modules: index.modules,
        unitOutputFiles: index.unitOutputFiles,
        location: location
      )
    } catch {
      throw RuntimeIndexError(error)
    }
  }

  func references(
    _ query: RuntimeIndexQuery,
    of symbolName: String,
    in index: RuntimeProjectIndex
  ) async throws(RuntimeIndexError) -> [RuntimeIndexReference] {
    let projectIndex = try await resolvedIndex(index)
    let references = switch query {
    case .conformers: projectIndex.conformers(of: symbolName)
    case .definitions: projectIndex.definitions(of: symbolName)
    case .directConformers: projectIndex.directConformers(of: symbolName)
    case .occurrences: projectIndex.occurrences(of: symbolName)
    case .references: projectIndex.references(to: symbolName)
    }
    return references.map(runtimeReference)
  }

  func occurrences(
    at location: DeclarationLocation,
    in index: RuntimeProjectIndex
  ) async throws(RuntimeIndexError) -> [RuntimeIndexReference] {
    let projectIndex = try await resolvedIndex(index)
    return projectIndex.occurrences(at: location).map(runtimeReference)
  }

  func definitions(
    in index: RuntimeProjectIndex
  ) async throws(RuntimeIndexError) -> [RuntimeIndexReference] {
    let projectIndex = try await resolvedIndex(index)
    return projectIndex.definitions().map(runtimeReference)
  }

  func references(
    to definitions: [RuntimeIndexReference],
    in index: RuntimeProjectIndex
  ) async throws(RuntimeIndexError) -> [RuntimeIndexReference] {
    let projectIndex = try await resolvedIndex(index)
    let identifiers = Set(definitions.map(\.symbol.usr))
    return projectIndex.references(toIdentifiers: identifiers)
      .map(runtimeReference)
  }

  private func resolvedIndex(_ index: RuntimeProjectIndex) async throws(
    RuntimeIndexError
  )
    -> ProjectIndex
  {
    do {
      return try await index.codebase.projectIndex(
        modules: index.modules, unitOutputFiles: index.unitOutputFiles
      )
    } catch {
      throw RuntimeIndexError(error)
    }
  }

  private func runtimeReference(
    _ reference: IndexReference
  ) -> RuntimeIndexReference {
    RuntimeIndexReference(
      symbol: RuntimeIndexSymbol(
        usr: reference.symbol.usr,
        name: reference.symbol.name,
        kind: runtimeKind(reference.symbol.kind)
      ),
      module: reference.module,
      file: reference.file,
      line: reference.line,
      column: reference.column,
      roles: runtimeRoles(reference.roles)
    )
  }

  func runtimeKind(
    _ kind: IndexSymbol.Kind
  ) -> RuntimeIndexSymbol.Kind {
    switch kind {
    case .module: .module
    case .enum: .enum
    case .struct: .struct
    case .class: .class
    case .protocol: .protocol
    case .extension: .extension
    case .typealias: .typealias
    case .function: .function
    case .variable: .variable
    case .instanceMethod: .instanceMethod
    case .classMethod: .classMethod
    case .staticMethod: .staticMethod
    case .instanceProperty: .instanceProperty
    case .classProperty: .classProperty
    case .staticProperty: .staticProperty
    case .initializer: .initializer
    case .deinitializer: .deinitializer
    case .enumCase: .enumCase
    case .parameter: .parameter
    case .other: .other
    }
  }

  func runtimeRoles(
    _ roles: SymbolRole
  ) -> Set<RuntimeSymbolRole> {
    Set(RuntimeSymbolRole.allCases.filter { role in
      roles.contains(indexRole(for: role))
    })
  }

  private func indexRole(for role: RuntimeSymbolRole) -> SymbolRole {
    switch role {
    case .declaration: .declaration
    case .definition: .definition
    case .reference: .reference
    case .read: .read
    case .write: .write
    case .call: .call
    case .dynamic: .dynamic
    case .implicit: .implicit
    case .childOf: .childOf
    case .baseOf: .baseOf
    case .overrideOf: .overrideOf
    case .receivedBy: .receivedBy
    case .calledBy: .calledBy
    case .extendedBy: .extendedBy
    case .accessorOf: .accessorOf
    case .containedBy: .containedBy
    case .specializationOf: .specializationOf
    }
  }
}

extension RuntimeIndexError {
  init(_ error: DependencyCheckError) {
    switch error {
    case let .unreadableCodebase(error): self = .unreadableCodebase(error)
    case let .indexUnavailable(error):
      self = .indexUnavailable(reason: error.description)
    default: self = .dependencyCheck(reason: error.description)
    }
  }

  init(_ error: IndexedLayeringError) {
    switch error {
    case let .invalidLayering(error): self = .invalidLayering(error)
    case let .unreadableCodebase(error): self = .unreadableCodebase(error)
    case let .indexUnavailable(error):
      self = .indexUnavailable(reason: error.description)
    }
  }

  init(_ error: ProjectIndexError) {
    switch error {
    case let .unreadableCodebase(error): self = .unreadableCodebase(error)
    case let .indexUnavailable(error):
      self = .indexUnavailable(reason: error.description)
    }
  }
}
