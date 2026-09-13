import Bylaws
import BylawsTestSupport
import Testing

@Suite("Sample app rules", .codebase(.sampleApp), .tags(.architecture))
struct SampleAppRulesTests {
  @Test(
    "ViewModels inherit from BaseViewModel",
    .annotatesViolations,
    arguments: try await SampleAppQueries.viewModels()
  )
  func viewModelInheritsBase(_ viewModel: Class) {
    #expect(viewModel.inherits(from: "BaseViewModel"))
  }

  @Test(
    "ViewModels are final",
    arguments: try await SampleAppQueries.viewModels()
  )
  func viewModelIsFinal(_ viewModel: Class) {
    #expect(viewModel.isFinal, sourceLocation: viewModel.testingLocation)
  }

  @Test("Trait binds the current codebase")
  func bindsCurrentCodebase() {
    #expect(Codebase.current == .sampleApp)
  }
}
