package enum SwiftPMTestRunnerError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  case noTestTargets
  case noMatchingTests
  case unsupportedEventVersion
  case incompleteRun
  case unexpectedIssue(String?)
  case processFailed(Int32, String)
  case processSignaled(Int32, String)
  case mismatchedReport
  case mismatchedCapture
  case cannotReadOutput(String, String)
  case cannotReadCommandOutput(command: String, root: String, reason: String)
  case malformedFilter(String)
  case reusedIndexDirectory
  case cannotLocateIndex

  package var description: String {
    switch self {
    case .noTestTargets:
      "The package has no test targets. Add a Swift Testing target to collect rules."
    case .noMatchingTests:
      "The test filter matched no Swift Testing functions. Check the filter and run again."
    case .unsupportedEventVersion:
      "Cannot read the Swift Testing event version. Use a supported Swift toolchain."
    case .incompleteRun:
      "The Swift Testing run did not finish. Run the tests again before source correction."
    case let .unexpectedIssue(test):
      "The Swift Testing run reported an unrelated failure\(test.map { " in '\($0)'" } ?? ""). Fix the failing test before source correction."
    case let .processFailed(status, output):
      "The SwiftPM command exited with status \(status). Fix the test or build failure before source correction.\n\(output)"
    case let .processSignaled(signal, output):
      "The SwiftPM command stopped after signal \(signal). Run the command again before source correction.\n\(output)"
    case .mismatchedReport:
      "The Swift Testing rule report must name a completed test from this run. Run the command again."
    case .mismatchedCapture:
      "The source capture must belong to the Swift Testing run. Run the command again."
    case let .cannotReadOutput(path, reason):
      "Cannot read the Swift Testing output at '\(path)': \(reason). Run the command again."
    case let .cannotReadCommandOutput(command, root, reason):
      "Cannot read the SwiftPM output from '\(command)' in '\(root)': \(reason). Check that the command returns JSON."
    case let .malformedFilter(filter):
      "Cannot read the test filter '\(filter)'. Use a regular expression."
    case .reusedIndexDirectory:
      "The compiler index must use a new build directory. Run the command again."
    case .cannotLocateIndex:
      "Cannot locate the compiler index. Check that swift build --show-bin-path returns one absolute path."
    }
  }
}
