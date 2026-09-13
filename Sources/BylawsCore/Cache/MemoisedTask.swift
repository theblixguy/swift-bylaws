import Foundation

package struct MemoisedTask<Value: Sendable, Failure: Error>: Sendable {
  private let id: UUID
  private let task: Task<Result<Value, Failure>, Never>

  package init(
    name: String,
    build: @escaping @Sendable () async throws(Failure) -> Value
  ) {
    id = UUID()
    // Task's initialiser accepts an untyped throwing operation alone, so the
    // failure travels as a Result and stays typed for the caller.
    task = Task(name: name) { @concurrent in
      await Result(catching: build)
    }
  }

  package static func value(
    name: String,
    lookup: () -> Self?,
    insert: (Self) -> Void,
    remove: () -> Void,
    storeValue: (Value) -> Void = { _ in },
    build: @escaping @Sendable () async throws(Failure) -> Value
  ) async throws(Failure) -> Value {
    let entry: Self
    if let existing = lookup() {
      entry = existing
    } else {
      entry = Self(name: name, build: build)
      insert(entry)
    }
    do {
      let value = try await entry.task.value.get()
      if lookup()?.id == entry.id {
        storeValue(value)
      }
      return value
    } catch {
      // A later request can replace a failed task while the caller is suspended.
      if lookup()?.id == entry.id {
        remove()
      }
      throw error
    }
  }
}
