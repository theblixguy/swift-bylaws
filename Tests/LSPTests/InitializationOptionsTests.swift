import BylawsPaths
import LanguageServerProtocol
import Testing
@testable import BylawsLSP

@Suite("LSP initialisation options")
struct InitializationOptionsTests {
  @Test("Missing options set zero refresh delay")
  func defaultDelay() {
    let options = InitializationOptions(nil, root: Self.root)

    #expect(options.refreshDelay == .zero)
  }

  @Test("Milliseconds set refresh duration")
  func millisecondsDelay() {
    let options = InitializationOptions(
      .dictionary(["refreshDelayMilliseconds": .int(300)]),
      root: Self.root
    )

    #expect(options.refreshDelay == .milliseconds(300))
  }

  @Test("String delay uses zero default")
  func stringDelay() {
    let options = InitializationOptions(
      .dictionary(["refreshDelayMilliseconds": .string("300")]),
      root: Self.root
    )

    #expect(options.refreshDelay == .zero)
  }

  @Test("Negative delay uses zero default")
  func negativeDelay() {
    let options = InitializationOptions(
      .dictionary(["refreshDelayMilliseconds": .int(-1)]),
      root: Self.root
    )

    #expect(options.refreshDelay == .zero)
  }

  private static let root = LexicalFilePath("/project")
}
