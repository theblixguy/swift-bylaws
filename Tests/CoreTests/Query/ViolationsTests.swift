import Bylaws
import BylawsTestSupport
import Testing

@Suite("Violations")
struct ViolationsTests {
  @Test("Offenders and rendered violations include the rule phrase")
  func offendersRender() async throws {
    let violations = try await Codebase.sampleApp.classes
      .suffixed("ViewModel")
      .violations(of: .inherits(from: "BaseViewModel"))

    #expect(violations.count == 1)
    #expect(violations.checkedCount == 3)
    #expect(!violations.isEmpty)
    #expect("\(violations)"
      .contains("violation of 'inherit from 'BaseViewModel''"))
    #expect("\(violations)".contains("BaseViewModel (BaseViewModel.swift:1)"))
  }

  @Test("A violation report renders as Markdown and attaches to the test")
  func markdownReport() async throws {
    let violations = try await Codebase.sampleApp.classes
      .suffixed("ViewModel")
      .violations(of: .inherits(from: "BaseViewModel"))

    #expect(violations.markdownReport
      .contains("Rule: inherit from 'BaseViewModel'"))
    #expect(violations.markdownReport
      .contains("- BaseViewModel (BaseViewModel.swift:1)"))
    violations.attachReport()
  }

  @Test("A matching-form ban negates the matcher phrase")
  func matchingFormBans() async throws {
    let violations = try await Codebase.sampleApp.files
      .violations(matching: .imports("UIKit") || .imports("SwiftUI"))

    #expect(violations.isEmpty)
    #expect(violations.rule.contains("not"))

    let foundationUsers = try await Codebase.sampleApp.files
      .violations(matching: .imports("Foundation"))
    #expect(foundationUsers.count == 2)
  }

  @Test("A clean selection produces no violations")
  func cleanSelection() async throws {
    let violations = try await SampleAppQueries.viewModels()
      .violations(of: .inherits(from: "BaseViewModel") && .isFinal)

    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 2)

    let rendered = "\(violations)"
    let expected =
      "no violations of 'inherit from 'BaseViewModel' and be final' (2 checked)"
    #expect(rendered == expected)
  }
}
