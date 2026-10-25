import BylawsSemantics

final class SwiftTestingReportSources {
  struct Edit: Codable {
    let snapshot: Int
    let range: Range<Int>
    let replacement: String
    let layout: SourceLayoutPlan?

    init(_ edit: SourceFix.Edit, snapshot: Int) {
      self.snapshot = snapshot
      range = edit.source.range
      replacement = edit.replacement
      layout = edit.layout
    }
  }

  private(set) var snapshots: [SourceSnapshot]
  private var indices: [SourceSnapshot: Int] = [:]
  private var sessions: [SourceLayoutComposition.Session?]

  init(snapshots: [SourceSnapshot] = []) {
    self.snapshots = snapshots
    sessions = Array(repeating: nil, count: snapshots.count)
    for (index, snapshot) in snapshots.enumerated()
      where indices[snapshot] == nil
    {
      indices[snapshot] = index
    }
  }

  func capture(_ edit: SourceFix.Edit) throws -> Edit {
    let index = index(for: edit.source.snapshot)
    try session(at: index).validate(edit)
    return Edit(edit, snapshot: index)
  }

  func captureCandidate(_ edit: SourceFix.Edit) throws -> Edit {
    let index = index(for: edit.source.snapshot)
    try session(at: index).validateCandidate(edit)
    return Edit(edit, snapshot: index)
  }

  func restore(_ captured: Edit) throws -> SourceFix.Edit {
    let edit = try edit(from: captured)
    try session(at: captured.snapshot).validate(edit)
    return edit
  }

  func restoreCandidate(_ captured: Edit) throws -> SourceFix.Edit {
    let edit = try edit(from: captured)
    try session(at: captured.snapshot).validateCandidate(edit)
    return edit
  }

  private func index(for snapshot: SourceSnapshot) -> Int {
    if let existing = indices[snapshot] { return existing }
    let index = snapshots.count
    snapshots.append(snapshot)
    sessions.append(nil)
    indices[snapshot] = index
    return index
  }

  private func session(at index: Int) -> SourceLayoutComposition.Session {
    if let session = sessions[index] { return session }
    let session = SourceLayoutComposition.Session(snapshot: snapshots[index])
    sessions[index] = session
    return session
  }

  private func edit(from captured: Edit) throws -> SourceFix.Edit {
    guard snapshots.indices.contains(captured.snapshot) else {
      throw SwiftTestingRuleSessionError.malformedReport(
        "Source snapshot index \(captured.snapshot) is outside the report's snapshot list"
      )
    }
    return SourceFix.Edit(
      source: try SourceSlice(
        snapshot: snapshots[captured.snapshot], range: captured.range
      ),
      replacement: captured.replacement, layout: captured.layout
    )
  }
}
