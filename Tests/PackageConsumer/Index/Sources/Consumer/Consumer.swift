import BylawsCore
import BylawsIndex
import BylawsIndexStore

public func index(for codebase: Codebase) async throws -> ProjectIndex {
  try await codebase.projectIndex()
}
