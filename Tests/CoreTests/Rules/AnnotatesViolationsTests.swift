import Bylaws
import BylawsTestSupport
import Testing

@Suite("Annotates violations")
struct AnnotatesViolationsTests {
  @Test(
    "Reflection finds the checked declaration",
    .annotatesViolations,
    arguments: try await SampleAppQueries.viewModels()
  )
  func bindsDeclarationLocation(_ viewModel: Class) {
    #expect(AnnotatesViolationsTrait.currentDeclarationLocation == viewModel
      .testingLocation)
  }

  @Test("Without the trait, no declaration location is bound")
  func noBindingWithoutTrait() {
    #expect(AnnotatesViolationsTrait.currentDeclarationLocation == nil)
  }
}

@Suite("Advisory composition", .advisory, .codebase(.sampleApp))
struct AdvisoryCompositionTests {
  @Test(
    "Relocation binds under an advisory suite",
    .annotatesViolations,
    arguments: try await SampleAppQueries.viewModels()
  )
  func bindsUnderAdvisorySuite(_ viewModel: Class) {
    #expect(
      AnnotatesViolationsTrait.currentDeclarationLocation
        == viewModel.testingLocation
    )
  }
}
