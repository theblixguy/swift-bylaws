package enum QueryInspection {
  @TaskLocal private static var sink: AsyncStream<SelectionInspection>
    .Continuation?

  package static var isEnabled: Bool { sink != nil }

  package static func record(
    query: String,
    selected: @autoclosure () -> [SelectionInspection.Element],
    previous: @autoclosure () -> [SelectionInspection.Element] = []
  ) {
    guard let sink else { return }
    let selected = selected()
    let retained = Set(selected)
    sink.yield(SelectionInspection(
      queryDescription: query,
      selected: selected,
      excluded: previous().filter { !retained.contains($0) }
    ))
  }

  static func collecting<Value>(
    _ body: () async -> Value
  ) async -> (value: Value, selections: [SelectionInspection]) {
    let (stream, continuation) = AsyncStream<SelectionInspection>.makeStream()
    let value = await $sink.withValue(continuation, operation: body)
    continuation.finish()
    var selections: [SelectionInspection] = []
    for await selection in stream { selections.append(selection) }
    return (value, selections)
  }
}
