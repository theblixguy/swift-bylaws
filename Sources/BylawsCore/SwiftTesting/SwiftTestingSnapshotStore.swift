import BylawsSemantics
import Foundation

final class SwiftTestingSnapshotStore: Sendable {
  static let codingKey = CodingUserInfoKey(rawValue: "swiftTestingSnapshots")!
  let directory: URL
  private let snapshots: [String: SourceSnapshot]

  init(directory: URL, snapshots: [String: SourceSnapshot] = [:]) {
    self.directory = directory
    self.snapshots = snapshots
  }

  static func reading(in directory: URL) throws -> SwiftTestingSnapshotStore {
    let store = SwiftTestingSnapshotStore(directory: directory)
    let sourceDirectory = directory.appendingPathComponent(
      "snapshots", isDirectory: true
    )
    guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
      return store
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: sourceDirectory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }
    var snapshots: [String: SourceSnapshot] = [:]
    for file in files {
      let id = file.deletingPathExtension().lastPathComponent
      snapshots[id] = try store.read(id)
    }
    return SwiftTestingSnapshotStore(directory: directory, snapshots: snapshots)
  }

  func write(_ snapshot: SourceSnapshot) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(snapshot)
    let id = SourceCapture.digest(data)
    let snapshots = directory.appendingPathComponent(
      "snapshots",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: snapshots, withIntermediateDirectories: true
    )
    let file = snapshots.appendingPathComponent(id + ".json")
    if !FileManager.default.fileExists(atPath: file.path) {
      try data.write(to: file, options: .atomic)
    }
    return id
  }

  func read(_ id: String) throws -> SourceSnapshot {
    guard id.utf8.count == 64,
          id.utf8
            .allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else {
      throw SwiftTestingRuleSessionError.malformedReport(
        "Source snapshot ID '\(id)' must contain 64 lowercase hexadecimal characters"
      )
    }
    if let cached = snapshots[id] { return cached }
    let file = directory.appendingPathComponent("snapshots", isDirectory: true)
      .appendingPathComponent(id + ".json")
    let data = try Data(contentsOf: file)
    guard SourceCapture.digest(data) == id else {
      throw SwiftTestingRuleSessionError.malformedReport(
        "Source snapshot '\(file.path)' differs from its recorded digest"
      )
    }
    return try JSONDecoder().decode(SourceSnapshot.self, from: data)
  }
}
