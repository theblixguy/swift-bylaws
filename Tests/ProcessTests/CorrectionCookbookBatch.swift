#if os(macOS) || os(Linux)
  import BylawsTestSupport
  import Foundation
  import Testing

  struct CorrectionCookbookBatch {
    struct Recipe {
      let mock: CorrectionCookbookMock
      let directory: String
      let functions: [String]
      let ruleIDs: [String]
      let source: String

      func file(
        _ path: String,
        in consumer: SwiftTestingReportConsumer
      ) -> URL {
        consumer.root.appendingPathComponent(directory)
          .appendingPathComponent(path)
      }
    }

    let recipes: [Recipe]
    var functions: [String] { recipes.flatMap(\.functions) }
    var ruleIDs: [String] { recipes.flatMap(\.ruleIDs) }

    init(_ mocks: [CorrectionCookbookMock]) throws {
      recipes = try mocks.enumerated().map { index, mock in
        let directory = "Cases/Recipe\(index)"
        let originalFunctions = try mock.swiftTestingFunctions()
        let functions = originalFunctions.map { "\($0)Recipe\(index)" }
        let ruleIDs = mock.ruleIDs.map { "\($0)-recipe-\(index)" }
        var source = try mock.swiftTestingSource()
        try #require(source.components(separatedBy: "root: .automatic()")
          .count == originalFunctions.count + 1)
        source = source.replacing(
          "root: .automatic()",
          with: "root: .directory(cookbookRoot.appendingPathComponent(\"\(directory)\").path)"
        )
        for (original, replacement) in zip(originalFunctions, functions) {
          try #require(source.contains("func \(original)()"))
          source = source.replacing(
            "func \(original)()",
            with: "func \(replacement)()"
          )
        }
        for (original, replacement) in zip(mock.ruleIDs, ruleIDs) {
          source = source.replacing(
            "report(ruleID: \"\(original)\"",
            with: "report(ruleID: \"\(replacement)\""
          )
        }
        return Recipe(
          mock: mock, directory: directory, functions: functions,
          ruleIDs: ruleIDs, source: source
        )
      }
    }

    var source: String {
      """
      import Foundation

      private let cookbookRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

      """ + recipes.map(\.source).joined(separator: "\n\n")
    }

    func writeSources(in consumer: SwiftTestingReportConsumer) throws {
      for recipe in recipes {
        for (path, source) in recipe.mock.sources {
          let file = recipe.file(path, in: consumer)
          try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try source.write(to: file, atomically: true, encoding: .utf8)
        }
      }
    }
  }
#endif
