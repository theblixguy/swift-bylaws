import BylawsSemantics
import Foundation

actor ParsedSyntaxNodeProjections {
  private struct WeakStorage {
    weak var value: SelectionStorage<SourceNode>?
    let identity: UUID
  }

  private static let maximumConcurrentFileTasks = max(
    1,
    ProcessInfo.processInfo.activeProcessorCount
  )

  private var values: [Set<SourceNode.Kind>: WeakStorage] = [:]
  private var tasks: [
    Set<SourceNode.Kind>: Task<SelectionStorage<SourceNode>, Never>
  ] = [:]

  func value(
    for kinds: Set<SourceNode.Kind>,
    files: [SourceFile]
  ) async -> SelectionStorage<SourceNode> {
    if let existing = values[kinds]?.value { return existing }
    if let task = tasks[kinds] { return await task.value }

    let identity = values[kinds]?.identity ?? UUID()
    let task = Task {
      let groups = await boundedConcurrentMap(
        files,
        maximumConcurrentTasks: Self.maximumConcurrentFileTasks
      ) { file in
        file.syntaxNodes(of: kinds)
      }
      return SelectionStorage(groups.flatMap(\.self), identity: identity)
    }
    tasks[kinds] = task
    let created = await task.value
    tasks[kinds] = nil
    values[kinds] = WeakStorage(value: created, identity: identity)
    return created
  }
}
