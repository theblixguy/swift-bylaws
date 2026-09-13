import BylawsCore
import BylawsSemantics

struct RuntimeSelection: Sendable {
  let family: SupportedAPI.DeclarationFamily
  let elements: [RuntimeModelValue]
  let queryDescription: String
  let rootPath: String?

  func narrowed(
    to elements: [RuntimeModelValue],
    queryDescription: String
  ) -> RuntimeSelection {
    QueryInspection.record(
      query: queryDescription,
      selected: elements.compactMap(Self.inspectionElement),
      previous: self.elements.compactMap(Self.inspectionElement)
    )
    return RuntimeSelection(
      family: family,
      elements: elements,
      queryDescription: queryDescription,
      rootPath: rootPath
    )
  }

  private static func inspectionElement(_ value: RuntimeModelValue)
    -> SelectionInspection.Element?
  {
    value.offender.map {
      SelectionInspection.Element(
        name: $0.name,
        description: $0.description,
        location: $0.location
      )
    }
  }
}
