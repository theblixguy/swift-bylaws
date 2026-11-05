import BylawsSemantics

struct RuntimeSourceList: Sendable {
  let source: SourceList<SourceSlice>
  let elements: [RuntimeValue]

  init<Element>(
    _ list: SourceList<Element>, element: (Element) -> RuntimeValue
  ) throws {
    source = try list.sourceSlices()
    elements = list.map(element)
  }
}
