import BylawsSemantics

enum RuntimeLayoutOperation: Sendable {
  enum Condition: Sendable {
    case between(RuntimeValue, RuntimeValue)
    case before(RuntimeValue)
    case after(RuntimeValue)
  }

  case layout(SourceLayout)
  case group(RuntimeLayoutGroup)
  case separator(SourceWhitespace)
  case conditionalSeparator(Condition, SourceWhitespace)
}

struct RuntimeLayoutGroup: Sendable {
  let projection: RuntimeValue?
  let predicate: RuntimeValue
  var comparison: RuntimeValue?

  init(
    projection: RuntimeValue? = nil,
    predicate: RuntimeValue,
    comparison: RuntimeValue? = nil
  ) {
    self.projection = projection
    self.predicate = predicate
    self.comparison = comparison
  }
}
