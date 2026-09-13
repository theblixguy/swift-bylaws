import BylawsSemantics
import Testing

@Suite("Visibility ordering")
struct VisibilityOrderingTests {
  @Test("Visibility levels use DSL names in order")
  func spellings() {
    #expect(
      Visibility.allCases.map(\.rawValue) == [
        "private", "fileprivate", "internal", "package", "public", "open",
      ]
    )
  }

  @Test("Visibility levels sort from private to open")
  func ordersLevels() {
    #expect(Visibility.private < .fileprivate)
    #expect(Visibility.internal < .public)
    #expect(Visibility.public < .open)
  }
}
