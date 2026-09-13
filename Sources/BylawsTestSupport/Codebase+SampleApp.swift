public import Bylaws
import BylawsPaths

extension Codebase {
  /// A codebase over the package's sample application.
  public static let sampleApp = Codebase(root: .directory(sampleAppRoot))
}

private let sampleAppRoot = LexicalFilePath(#filePath)
  .removingLastComponent()
  .removingLastComponent()
  .removingLastComponent()
  .appending("Tests/SampleApp")
  .string
