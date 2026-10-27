import Foundation

package enum RuleRunPurpose: String, Sendable {
  case checkOnly
  case proposeCorrections

  package static let environmentKey = "BYLAWS_RULE_RUN_PURPOSE"

  @TaskLocal package static var current: RuleRunPurpose = launchPurpose

  private static let launchPurpose = ProcessInfo.processInfo
    .environment[environmentKey].flatMap(Self.init(rawValue:))
    ?? .proposeCorrections
}
