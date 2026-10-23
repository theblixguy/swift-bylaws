import BylawsSemantics

enum RuntimeLayoutOperation: Sendable {
  enum Condition: Sendable {
    case between(RuntimeValue, RuntimeValue)
    case before(RuntimeValue)
    case after(RuntimeValue)
  }

  case group(predicate: RuntimeValue, comparison: RuntimeValue?)
  case separator(SourceWhitespace)
  case conditionalSeparator(Condition, SourceWhitespace)
}
