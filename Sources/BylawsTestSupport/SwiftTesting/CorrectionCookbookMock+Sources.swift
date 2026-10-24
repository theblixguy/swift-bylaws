import Foundation
import Testing

extension CorrectionCookbookMock {
  package func bylawsSource() throws -> String {
    let snippets = try snippets { "Rule(\"\($0)\"" }
    if snippets.count == 1 { return configured(try #require(snippets.first)) }

    let declaration = "nonisolated let rules: [Rule] = ["
    let parts = try snippets.map { snippet in
      let parts = snippet.components(separatedBy: declaration)
      try #require(parts.count == 2)
      try #require(parts[1].hasSuffix("\n]"))
      return (prefix: parts[0], body: String(parts[1].dropLast(2)))
    }
    let prefix = try #require(parts.first).prefix
    return configured(
      prefix + "nonisolated let maximumWidth: Int? = nil\n\n"
        + declaration + parts.map(\.body).joined(separator: "\n") + "\n]"
    )
  }

  package func swiftTestingSource() throws -> String {
    configured(try snippets { "report(ruleID: \"\($0)\"" }
      .joined(separator: "\n\n"))
  }

  package func swiftTestingFunctions() throws -> [String] {
    try snippets { "report(ruleID: \"\($0)\"" }.map { snippet in
      let declaration = try #require(snippet.components(separatedBy: "\n")
        .first { $0.hasPrefix("func ") })
      return try #require(declaration.dropFirst(5).split(separator: "(").first)
        .description
    }
  }

  private func snippets(matching signature: (String) -> String) throws
    -> [String]
  {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let path = root.appendingPathComponent(
      "Sources/Bylaws/Bylaws.docc/\(article).md"
    )
    let article = try String(contentsOf: path, encoding: .utf8)
    let blocks = article.components(separatedBy: "```swift\n").dropFirst()
      .compactMap { $0.components(separatedBy: "\n```").first }
    return try ruleIDs.map { id in
      let matches = blocks.filter { $0.contains(signature(id)) }
      try #require(matches.count == 1, "\(id): \(path.path)")
      return try #require(matches.first)
    }
  }

  private func configured(_ source: String) -> String {
    source.replacing(
      "maximumWidth: Int? = nil",
      with: "maximumWidth: Int? = \(maximumWidth.map(String.init) ?? "nil")"
    )
  }
}
