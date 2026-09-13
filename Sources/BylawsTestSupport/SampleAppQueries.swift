public import Bylaws

/// Queries over the sample app shared by multiple test suites.
public enum SampleAppQueries {
  /// Returns the sample app's view-model classes without the base class.
  public static func viewModels() async throws -> Selection<Class> {
    try await Codebase.sampleApp.classes
      .suffixed("ViewModel")
      .excluding("BaseViewModel")
  }
}
