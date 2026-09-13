import BylawsSemantics

struct RuntimeManifestList: Sendable {
  let knownValues: [RuntimeValue]
  let conditionalValues: [RuntimeValue]
  let unresolvedValues: [RuntimeModelValue]

  var isComplete: Bool {
    conditionalValues.isEmpty && unresolvedValues.isEmpty
  }

  var possibleValues: [RuntimeValue] {
    knownValues + conditionalValues
  }

  var values: [RuntimeValue]? {
    isComplete ? knownValues : nil
  }

  init<Element: Sendable & Hashable & Codable>(
    _ list: ManifestList<Element>,
    transform: (Element) -> RuntimeValue
  ) {
    knownValues = list.knownValues.map(transform)
    conditionalValues = list.conditionalValues.map(transform)
    unresolvedValues = list.unresolvedValues.map(
      { .manifest(.unresolvedValue($0)) }
    )
  }
}
