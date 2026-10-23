import BylawsIndexStore
import Foundation

extension ProjectIndexCache {
  // The wrapper avoids a task-local crash on Swift 6.3.3.
  package struct IndexStoreBuilder: Sendable {
    package let build: @Sendable (String) async throws -> String

    package init(build: @escaping @Sendable (String) async throws -> String) {
      self.build = build
    }
  }

  @TaskLocal package static var indexStoreBuilder: IndexStoreBuilder?

  static func correctionIndexStore(
    forRoot root: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async throws(IndexStoreError) -> String? {
    guard environment["BYLAWS_SOURCE_ONLY"] != "1" else {
      throw .unreadablePath(
        path: root,
        reason: "compiler-index queries cannot run with --source-only"
      )
    }
    if let indexStoreBuilder {
      do {
        return try await indexStoreBuilder.build(root)
      } catch {
        throw .unreadablePath(path: root, reason: String(describing: error))
      }
    }
    guard environment["BYLAWS_CORRECTION_ACTIVE"] == "1" else { return nil }
    guard let builtRoot = environment["BYLAWS_FRESH_INDEX_ROOT"],
          let store = environment["BYLAWS_FRESH_INDEX_STORE"],
          URL(fileURLWithPath: builtRoot).resolvingSymlinksInPath().path
          == URL(fileURLWithPath: root).resolvingSymlinksInPath().path
    else {
      throw .unreadablePath(
        path: root,
        reason: "correction needs a fresh compiler index for '\(root)'; use the SwiftPM package built by this run"
      )
    }
    return store
  }
}
