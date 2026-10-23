import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner

@Suite("Correction application")
struct CorrectionApplicationTests {
  @Test(
    "Application error preserves cause and lists changed files",
    arguments: [
      ([String](), "No files changed."),
      (["/First.swift"], "Changed files: /First.swift."),
      (
        ["/First.swift", "/Second.swift"],
        "Changed files: /First.swift, /Second.swift."
      ),
    ]
  )
  func errorDescription(changedPaths: [String], expectedChanges: String) {
    let error = CorrectionPlan.ApplicationError(
      changedPaths: changedPaths, failedPath: "/Failed.swift",
      reason: "the source changed before replacement.\nRun the command again."
    )
    let expected = """
    cannot apply the correction at '/Failed.swift': the source changed before replacement.
    Run the command again.
    \(expectedChanges)
    """

    #expect(error.description == expected)
  }

  @Test("Changed captured dependency stops application before source writes")
  func staleCapture() async throws {
    let project = try TemporaryProject(files: [
      "First.swift": "let first = 1\n",
      "Second.swift": "let second = 2\n",
      "Dependency.swift": "struct Dependency {}\n",
    ])
    let plan = try prepare(in: project, replacements: [
      "First.swift": "let first = 3\n",
      "Second.swift": "let second = 4\n",
    ])
    let capture = try await SourceCapture.capture(.init(
      rootPath: project.rootURL.path,
      selection: .sourceFiles(
        including: ["*.swift"], excluding: [], swiftPM: false, xcode: false
      )
    ))
    try #require(capture.inputs.contains {
      $0.path == project.fileURL(for: "Dependency.swift").path
    })
    try await SourceCapture.validate([capture])
    try project.write("struct Changed {}\n", to: "Dependency.swift")

    await #expect(throws: CaptureError.self) {
      try await plan.apply(captures: [capture])
    }

    #expect(try Data(contentsOf: project.fileURL(for: "First.swift"))
      == Data("let first = 1\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Second.swift"))
      == Data("let second = 2\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Dependency.swift"))
      == Data("struct Changed {}\n".utf8))
    let remaining = try FileManager.default.contentsOfDirectory(
      atPath: project.rootURL.path
    )
    #expect(remaining.sorted()
      == ["Dependency.swift", "First.swift", "Second.swift"])
  }

  @Test("Later staging failure removes earlier temporary files")
  func stagingFailure() async throws {
    let project = try TemporaryProject(files: [
      "First.swift": "let first = 1\n",
      "Second.swift": "let second = 2\n",
    ])
    let plan = try prepare(in: project, replacements: [
      "First.swift": "let first = 3\n",
      "Second.swift": "let second = 4\n",
    ])
    let first = project.fileURL(for: "First.swift")
    let second = project.fileURL(for: "Second.swift")
    try #require(plan.changes.map(\.path) == [first.path, second.path])
    try project.removeFile(at: "Second.swift")

    await #expect {
      try await plan.apply(captures: [])
    } throws: { error in
      guard let error = error as? CorrectionPlan.ApplicationError else {
        return false
      }
      return error.changedPaths.isEmpty && error.failedPath == second.path
    }

    #expect(try Data(contentsOf: first) == Data("let first = 1\n".utf8))
    #expect(!FileManager.default.fileExists(atPath: second.path))
    let remaining = try FileManager.default.contentsOfDirectory(
      atPath: project.rootURL.path
    )
    #expect(remaining == ["First.swift"])
  }

  @Test("Later replacement failure reports retained earlier changes")
  func partialReplacement() async throws {
    let project = try TemporaryProject(files: [
      "First.swift": "let first = 1\n",
      "Second.swift": "let second = 2\n",
    ])
    let plan = try prepare(in: project, replacements: [
      "First.swift": "let first = 3\n",
      "Second.swift": "let second = 4\n",
    ])
    let first = project.fileURL(for: "First.swift")
    let second = project.fileURL(for: "Second.swift")
    let alias = project.fileURL(for: "Alias.swift")
    try #require(plan.changes.map(\.path) == [first.path, second.path])
    try FileManager.default.linkItem(at: second, to: alias)

    await #expect {
      try await plan.apply(captures: [])
    } throws: { error in
      guard let error = error as? CorrectionPlan.ApplicationError else {
        return false
      }
      return error.changedPaths == [first.path]
        && error.failedPath == second.path
    }

    #expect(try Data(contentsOf: first) == Data("let first = 3\n".utf8))
    #expect(try Data(contentsOf: second) == Data("let second = 2\n".utf8))
    #expect(try Data(contentsOf: alias) == Data("let second = 2\n".utf8))
    let remaining = try FileManager.default.contentsOfDirectory(
      atPath: project.rootURL.path
    )
    #expect(remaining.sorted() == [
      "Alias.swift",
      "First.swift",
      "Second.swift",
    ])
  }

  @Test("Replacement retains file permissions", arguments: [0o640, 0o755])
  func permissions(mode: Int) async throws {
    let project = try TemporaryProject(files: ["App.swift": "let value = 1\n"])
    let destination = project.fileURL(for: "App.swift")
    try FileManager.default.setAttributes(
      [.posixPermissions: mode], ofItemAtPath: destination.path
    )
    let plan = try prepare(in: project, replacements: [
      "App.swift": "let value = 2\n",
    ])

    let changed = try await plan.apply(captures: [])

    #expect(changed == [destination.path])
    #expect(try Data(contentsOf: destination) == Data("let value = 2\n".utf8))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: destination.path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == mode)
  }

  private func prepare(
    in project: TemporaryProject, replacements: [String: String]
  ) throws -> CorrectionPlan {
    let fixes = try replacements.sorted { $0.key < $1.key }.map { path, text in
      let file = try FileCollector
        .collect(fileAt: project.fileURL(for: path).path)
      return SourceFix(edits: [try file.source.replacement(with: text)])
    }
    let offenders = fixes.map {
      Offender(
        description: "source correction",
        location: .start(of: $0.edits[0].source.filePath)
      )
    }
    let report = RuleReport(
      id: "source", name: "Source matches rule", enforcement: .enforced,
      hint: nil,
      location: .start(of: project.fileURL(for: "Bylaws.swift").path),
      violations: Violations(
        rule: "match rule", offenders: offenders, checkedCount: offenders.count,
        witnesses: Array(repeating: nil, count: offenders.count),
        fixes: fixes.map(Optional.some)
      ),
      warnings: []
    )
    let plan = CorrectionPlan.prepare(
      reports: [report],
      rootPath: project.rootURL.path
    )
    try #require(plan.diagnostics.isEmpty)
    try #require(plan.changes.count == replacements.count)
    return plan
  }
}
