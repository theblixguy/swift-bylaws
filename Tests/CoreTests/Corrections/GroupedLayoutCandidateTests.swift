import Bylaws
import BylawsCore
import Foundation
import Testing

@Suite("Passing group layout context")
struct GroupedLayoutCandidateTests {
  @Test("Passing groups expose no edits and retain context")
  func passingGroups() throws {
    let file = try FileCollector.collect(
      source: source, path: "/virtual/Panel.swift"
    )
    let fix = try file.structs[0].properties.replacement {
      Group(where: { _ in true })
    }

    #expect(fix.edits.isEmpty)
    #expect(fix.layoutCandidates.count == 1)
    let candidate = try #require(fix.layoutCandidates.first)
    #expect(candidate.source.text == "let first = 1\n  let second = 2")
    #expect(candidate.replacement == "let first = 1\n  let second = 2")
  }

  @Test("Correction builder retains passing group context")
  func selection() async throws {
    let codebase = Codebase(root: .sources(["Sources/Panel.swift": source]))
    let violations = try await codebase.structs.violations("Group properties") {
      declaration in
      try declaration.properties.replacement {
        Group(where: { _ in true })
      }
    }

    #expect(violations.isEmpty)
    #expect(violations.fixes.isEmpty)
    #expect(violations.layoutCandidates.count == 1)
    let candidate = try #require(violations.layoutCandidates.first)
    try candidate.validateLayoutCandidate()
    #expect(candidate.source.file.text == source)
  }

  @Test("Correction transport retains group context")
  func transport() throws {
    let file = try FileCollector.collect(
      source: source, path: "/virtual/Panel.swift"
    )
    let original = try file.structs[0].properties.replacement {
      Group(where: { _ in true })
    }
    let decoded = try JSONDecoder().decode(
      SourceFix.self, from: JSONEncoder().encode(original)
    )
    let candidate = try #require(decoded.layoutCandidates.first)

    #expect(decoded.edits.isEmpty)
    #expect(decoded.layoutCandidates.count == 1)
    #expect(candidate.source.file.text == source)
    try candidate.validateLayoutCandidate()
  }

  @Test("Older corrections decode without layout context")
  func olderCorrection() throws {
    let decoded = try JSONDecoder().decode(
      SourceFix.self, from: Data(#"{"edits":[]}"#.utf8)
    )

    #expect(decoded.title == nil)
    #expect(decoded.edits.isEmpty)
    #expect(decoded.layoutCandidates.isEmpty)
  }

  @Test("Raw replacements cannot become passing layout context")
  func rawCandidate() throws {
    let file = try FileCollector.collect(
      source: source, path: "/virtual/Panel.swift"
    )
    let candidate = try file.source.replacement(with: source)
    let malformed = SourceFix(edits: [], layoutCandidates: [candidate])

    #expect(throws: SourceLayoutComposition.Failure.self) {
      try JSONEncoder().encode(malformed)
    }
  }

  private let source = "struct Panel {\n  let first = 1\n  let second = 2\n}"
}
