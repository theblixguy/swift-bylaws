package enum RuleDependencyTracking {
  @TaskLocal
  private static var collector: Collector?

  package static func record(_ dependency: RuleDependency) async {
    await collector?.record(dependency)
  }

  package static func recordUntrackedDependency() async {
    await collector?.recordUntrackedDependency()
  }

  package static func collecting<Value, Failure: Error>(
    _ body: () async throws(Failure) -> Value
  ) async throws(Failure) -> (
    value: Value,
    dependencies: Set<RuleDependency>,
    isComplete: Bool
  ) {
    let collector = Collector()
    let result: Result<Value, Failure> = await $collector.withValue(collector) {
      await Result(catching: body)
    }
    let collected = await collector.result
    return (try result.get(), collected.dependencies, collected.isComplete)
  }

  private actor Collector {
    private var dependencies: Set<RuleDependency> = []
    private var isComplete = true

    var result: (
      dependencies: Set<RuleDependency>,
      isComplete: Bool
    ) {
      (dependencies, isComplete)
    }

    func record(_ dependency: RuleDependency) {
      dependencies.insert(dependency)
    }

    func recordUntrackedDependency() {
      isComplete = false
    }
  }
}
