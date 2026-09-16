import BylawsPaths
import Foundation
package import BylawsSemantics

package struct ParsedCodebase: Sendable {
  package enum Declarations: Sendable, Hashable {
    case asWritten
    case resolved
  }

  package enum Projection: Sendable, Hashable {
    case files
    case classes
    case actors
    case structs
    case enums
    case types
    case protocols
    case extensions
    case functions
    case properties
    case initializers
    case imports
    case typealiases
    case calls
    case expressions
    case assignments
    case variableBindings
    case compilationBranches
  }

  package let rootPath: String
  package let filesAsWritten: [SourceFile]
  private let inheritance = ResolvedInheritance()
  private let projections = ParsedCodebaseProjections()

  package func projection<Element: Sendable>(
    for category: Projection,
    declarations: Declarations = .resolved,
    create: @escaping @Sendable ([SourceFile]) -> [Element]
  ) async -> SelectionStorage<Element> {
    let files = switch declarations {
    case .asWritten: filesAsWritten
    case .resolved: await resolvedFiles()
    }
    return await projections.value(
      for: category,
      declarations: declarations
    ) { create(files) }
  }

  package init(rootPath: String, files rawFiles: [SourceFile]) {
    self.rootPath = rootPath

    filesAsWritten = rawFiles
  }

  package func resolvedFiles() async -> [SourceFile] {
    await inheritance.files(resolving: filesAsWritten)
  }

  package var rootName: String {
    LexicalFilePath(rootPath).lastComponent ?? rootPath
  }
}

private actor ParsedCodebaseProjections {
  private struct WeakStorage {
    weak var value: AnyObject?
    let identity: UUID
  }

  private struct Key: Hashable {
    let category: ParsedCodebase.Projection
    let declarations: ParsedCodebase.Declarations
  }

  private var values: [Key: WeakStorage] = [:]

  func value<Element: Sendable>(
    for category: ParsedCodebase.Projection,
    declarations: ParsedCodebase.Declarations,
    create: @Sendable () -> [Element]
  ) -> SelectionStorage<Element> {
    let key = Key(category: category, declarations: declarations)
    if let existing = values[key]?.value as? SelectionStorage<Element> {
      return existing
    }
    let identity = values[key]?.identity ?? UUID()
    let created = SelectionStorage(create(), identity: identity)
    values[key] = WeakStorage(value: created, identity: identity)
    return created
  }
}

private actor ResolvedInheritance {
  private var resolved: [SourceFile]?

  func files(resolving files: [SourceFile]) -> [SourceFile] {
    if let resolved { return resolved }
    let resolved = InheritanceResolver.resolve(in: files)
    self.resolved = resolved
    return resolved
  }
}
