import BylawsPaths
import Foundation
package import BylawsSemantics

package struct ParsedCodebase: Sendable {
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
  package let files: [SourceFile]
  private let projections = ParsedCodebaseProjections()

  package func projection<Element: Sendable>(
    for category: Projection,
    create: @escaping @Sendable ([SourceFile]) -> [Element]
  ) async -> SelectionStorage<Element> {
    let files = files
    return await projections.value(for: category) { create(files) }
  }

  package init(rootPath: String, files rawFiles: [SourceFile]) {
    self.rootPath = rootPath

    files = InheritanceResolver.resolve(in: rawFiles)
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

  private var values: [ParsedCodebase.Projection: WeakStorage] = [:]

  func value<Element: Sendable>(
    for category: ParsedCodebase.Projection,
    create: @Sendable () -> [Element]
  ) -> SelectionStorage<Element> {
    if let existing = values[category]?.value as? SelectionStorage<Element> {
      return existing
    }
    let identity = values[category]?.identity ?? UUID()
    let created = SelectionStorage(create(), identity: identity)
    values[category] = WeakStorage(value: created, identity: identity)
    return created
  }
}
