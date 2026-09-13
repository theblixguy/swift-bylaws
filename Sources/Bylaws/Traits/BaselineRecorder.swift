import BylawsCore
import Foundation

package actor BaselineRecorder {
  private var recordings: [String: Recording] = [:]

  package init() {}

  package func record(
    _ entries: Set<Baseline.Entry>,
    completedRules: Set<Rule.ID>,
    in baseline: Baseline
  ) throws -> Int {
    guard BaselineFile.isValidIdentifier(baseline.name) else {
      throw BaselineRecordingError.invalidName(baseline.name)
    }
    var recording = recordings[baseline.file, default: Recording()]
    recording.entries.formUnion(entries)
    recording.completedRules.formUnion(completedRules)
    recordings[baseline.file] = recording
    let preserved = baseline.entries.filter {
      !recording.completedRules.contains($0.rule)
    }
    let updated = Set(preserved).union(recording.entries)
    try BaselineFile.render(name: baseline.name, entries: Array(updated))
      .write(toFile: baseline.file, atomically: true, encoding: .utf8)
    return updated.count
  }

  private struct Recording {
    var completedRules: Set<Rule.ID> = []
    var entries: Set<Baseline.Entry> = []
  }
}

package enum BaselineRecordingError:
  Error, Sendable, Hashable, CustomStringConvertible
{
  case invalidName(String)

  package var description: String {
    switch self {
    case let .invalidName(name):
      "The baseline name '\(name)' must use ASCII letters, digits and "
        + "underscores and begin with a letter or underscore. Rename the "
        + "declaring property to match."
    }
  }
}
