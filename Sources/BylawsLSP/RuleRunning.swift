import BylawsRunner

struct RuleRunning: Sendable {
  let run: @Sendable (
    RuleRunConfiguration
  ) async throws(CancellationError) -> RuleRunResult

  let discardCaches: @Sendable (_ rootPath: String) async -> Void

  static let standard = Self(
    run: RuleRunner.run,
    discardCaches: RuleRunner.discardCaches(under:)
  )
}
