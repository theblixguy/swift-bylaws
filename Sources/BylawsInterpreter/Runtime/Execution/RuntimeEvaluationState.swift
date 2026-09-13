struct RuntimeLimits: Sendable {
  let maximumInstructions: Int
  let maximumCallDepth: Int

  static let standard = RuntimeLimits(
    maximumInstructions: 100_000,
    maximumCallDepth: 128
  )
}

struct RuntimeEvaluationState {
  var remainingInstructions: Int
  var callDepth = 0
  var synchronousClosureDepth = 0
  let maximumCallDepth: Int

  init(limits: RuntimeLimits) {
    remainingInstructions = limits.maximumInstructions
    maximumCallDepth = limits.maximumCallDepth
  }
}
