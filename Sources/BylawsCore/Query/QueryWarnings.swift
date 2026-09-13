// A query filter runs synchronously. The stream carries its warnings into
// the rule's asynchronous scope.
package enum QueryWarnings {
  @TaskLocal
  fileprivate static var sink: AsyncStream<Rule.Warning>.Continuation?

  package static func record(_ warning: Rule.Warning) {
    sink?.yield(warning)
  }

  package static func collecting<Value>(
    _ body: () async throws -> Value
  ) async rethrows -> (value: Value, warnings: [Rule.Warning]) {
    let (stream, continuation) = AsyncStream<Rule.Warning>.makeStream()
    let value = try await $sink.withValue(continuation, operation: body)
    continuation.finish()
    var warnings: [Rule.Warning] = []
    for await warning in stream where !warnings.contains(warning) {
      warnings.append(warning)
    }
    return (value, warnings)
  }
}
