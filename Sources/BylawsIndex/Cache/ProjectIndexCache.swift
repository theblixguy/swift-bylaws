package import BylawsCore
import BylawsPaths
package import BylawsIndexStore
import Foundation

package actor ProjectIndexCache {
  package static let shared = ProjectIndexCache()

  package init() {}

  package private(set) var readCount = 0

  package func index(
    for codebase: Codebase,
    modules: Set<String>?,
    unitOutputFiles: Set<String>?
  ) async throws(ProjectIndexError) -> ProjectIndex {
    let root = try codebase.indexRootPath()
    let key = Key(
      root: root,
      modules: modules,
      unitOutputFiles: unitOutputFiles,
      including: modules == nil ? codebase.including : nil,
      excluding: modules == nil ? codebase.excluding : nil
    )
    do {
      let index = try await MemoisedTask.value(
        name: "bylaws: read index store",
        lookup: { entries[key] },
        insert: { entry in
          entries[key] = entry
          readCount += 1
        },
        remove: { entries[key] = nil }
      ) { () throws(IndexStoreError) in
        let path = try IndexStoreLocation.path(forPackageAt: root)
        let store = try IndexStore(path: path)
        let rootPath = LexicalFilePath(root)
        return try ProjectIndex(
          store: store,
          modules: modules,
          unitOutputFiles: unitOutputFiles,
          includingFile: { file in
            if modules != nil { return true }
            guard file.hasSuffix(".swift"),
                  let relative = LexicalFilePath(file).relative(to: rootPath)
            else { return false }
            return codebase.covers(Glob.Path(relative.string))
          }
        )
      }
      await RuleDependencyTracking.recordUntrackedDependency()
      return index
    } catch {
      throw .indexUnavailable(error)
    }
  }

  package func removeEntries(under directory: String) {
    entries = entries.filter {
      !LexicalFilePath(directory).contains(LexicalFilePath($0.key.root))
    }
  }

  private struct Key: Hashable {
    let root: String
    let modules: Set<String>?
    let unitOutputFiles: Set<String>?
    let including: [Glob]?
    let excluding: [Glob]?
  }

  private var entries: [Key: MemoisedTask<ProjectIndex, IndexStoreError>] = [:]
}
