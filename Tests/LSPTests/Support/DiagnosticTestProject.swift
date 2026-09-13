import BylawsTestSupport
import Foundation

final class DiagnosticTestProject {
  private let project: TemporaryProject
  var root: URL { project.rootURL }
  var source: URL { project.fileURL(for: "Sources/App/App.swift") }
  var rules: URL { project.fileURL(for: "Bylaws.swift") }

  init(
    source sourceText: String = "class Bad {}",
    rules: String? = DiagnosticTestProject.rules,
    files additionalFiles: [String: String] = [:]
  ) throws {
    var files = [
      "Sources/App/App.swift": sourceText,
      "Package.swift": "",
    ]
    if let rules {
      files["Bylaws.swift"] = rules
    }
    files.merge(additionalFiles) { _, replacement in replacement }
    project = try TemporaryProject(
      files: files,
      directoryNamePrefix: "bylaws-lsp"
    )
  }

  func removeRules() throws {
    try project.removeFile(at: "Bylaws.swift")
  }

  func writeSource(_ source: String) throws {
    try project.write(source, to: "Sources/App/App.swift")
  }

  func writeRules(_ rules: String) throws {
    try project.write(rules, to: "Bylaws.swift")
  }

  static let invalidRules = """
  let app = Codebase(including: ["Sources/**"])

  Rule("final-classes", "Classes are final") {
    app.classes.violations(of: .isFinal
  }
  """

  private static let rules = """
  let app = Codebase(including: ["Sources/**"])

  Rule("final-classes", "Classes are final") {
    app.classes.violations(of: .isFinal)
  }
  """
}
