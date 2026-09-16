import BylawsSemantics
@testable import BylawsCore

extension ParseCache {
  func sourceFile(
    forSource source: String,
    at path: String,
    swiftLanguageMode: SwiftLanguageMode = .v6
  ) async -> SourceFile? {
    let key = Self.key(forSource: source, swiftLanguageMode: swiftLanguageMode)
    guard let file = await sourceFile(forKey: key, at: path),
          file.sourceText == source, file.swiftLanguageMode == swiftLanguageMode
    else { return nil }
    return file
  }

  func store(_ file: SourceFile) async {
    await store(file, forKey: Self.key(
      forSource: file.sourceText, swiftLanguageMode: file.swiftLanguageMode
    ))
  }
}
