import ArgumentParser
import Testing
@testable import bylaws_cli

@Suite("CLI help")
struct CLIHelpTests {
  @Test("Lint help shows common workflows")
  func lint() {
    let help = BylawsCommand.helpMessage(
      for: LintCommand.self,
      columns: 120
    )

    #expect(help.contains("bylaws lint --report-path Sources/Domain"))
    #expect(help.contains(
      "bylaws lint --changed-path Sources/Checkout/CheckoutView.swift"
    ))
    #expect(help.contains("bylaws lint --format json --output report.json"))
    #expect(help.contains(
      "Limit reported violations, source warnings and the violation exit status"
    ))
    #expect(help.contains(
      "https://theblixguy.github.io/swift-bylaws/documentation/bylaws/runningrulesfromthecli"
    ))
  }

  @Test("Rules help shows listing and inspection workflows")
  func rules() {
    let help = BylawsCommand.helpMessage(
      for: RulesCommand.self,
      columns: 120
    )

    #expect(help.contains("bylaws rules --for Sources/Billing"))
    #expect(help.contains("bylaws rules --explain layers"))
  }

  @Test("Init help shows the setup workflow")
  func initialize() {
    let help = BylawsCommand.helpMessage(
      for: InitCommand.self,
      columns: 120
    )

    #expect(help.contains("bylaws init"))
    #expect(help.contains("bylaws lint"))
    #expect(help.contains("bylaws init --path Config/Bylaws.swift"))
  }
}
