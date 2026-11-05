import BylawsSemantics

extension RuntimeEvaluator {
  func layoutCondition(_ arguments: RuntimeArguments) throws(RuntimeError)
    -> RuntimeValue
  {
    try arguments.requireLabels([nil] as [String?], for: "maximumLineLength")
    let condition: SourceLayoutCondition = switch try arguments.value(at: 0) {
    case let .integerRange(range): .maximumLineLength(range)
    case let .integerClosedRange(range): .maximumLineLength(range)
    case let .integerRangeFrom(range): .maximumLineLength(range)
    case let .integerRangeThrough(range): .maximumLineLength(range)
    case let .integerRangeUpTo(range): .maximumLineLength(range)
    default: throw RuntimeError(
        message: "maximumLineLength takes one Int range",
        location: arguments.location
      )
    }
    return .sourceLayoutCondition(condition)
  }

  func layoutCondition(
    in arguments: RuntimeArguments,
    at index: Int
  ) throws(RuntimeError) -> SourceLayoutCondition? {
    switch try arguments.value(at: index) {
    case let .sourceLayoutCondition(condition),
         let .optional(.sourceLayoutCondition(condition)): condition
    case .optional(nil): nil
    default: throw RuntimeError(
        message: "Layout condition must be SourceLayoutCondition or nil",
        location: arguments.location
      )
    }
  }
}
