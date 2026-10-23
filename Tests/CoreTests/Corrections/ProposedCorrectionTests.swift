import Bylaws
import BylawsCore
import Testing

@Suite("Corrections as rule checks")
struct ProposedCorrectionTests {
  @Test("Changed edits identify offenders and preserve checked count")
  func changedEdits() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Models.swift": "class Old {}\nclass Current {}",
    ]))
    let violations = try await codebase.classes
      .violations("Use current name") { declaration in
        let name = try declaration.nameSource
        name.replacement(with: name.text)
        if declaration.name == "Old" {
          name.replacement(with: "Updated")
        }
      }
    let fix = try #require(violations.fixes.first ?? nil)

    #expect(violations.checkedCount == 2)
    #expect(violations.offenders.map(\.name) == ["Old"])
    #expect(fix.edits.count == 1)
    #expect(fix.edits.first?.source.text == "Old")
    #expect(fix.edits.first?.replacement == "Updated")
  }

  @Test("Empty and unchanged proposals produce no violations")
  func noChanges() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Model.swift": "class Model {}",
    ]))
    let empty = try await codebase.classes
      .violations("Keep declaration") { _ in }
    let unchanged = try await codebase.classes
      .violations("Keep spelling") { declaration in
        let source = try declaration.source
        source.replacement(with: source.text)
      }

    #expect(empty.checkedCount == 1)
    #expect(empty.offenders.isEmpty)
    #expect(empty.fixes.isEmpty)
    #expect(unchanged.checkedCount == 1)
    #expect(unchanged.offenders.isEmpty)
    #expect(unchanged.fixes.isEmpty)
  }

  @Test("Canonically equal Unicode with different bytes produces correction")
  func exactBytes() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Model.swift": "let caf\u{E9} = 1",
    ]))
    let violations = try await codebase.properties
      .violations("Use decomposed spelling") { property in
        try property.nameSource.replacement(with: "cafe\u{301}")
      }
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(violations.offenders.count == 1)
    #expect(edit.source.text == edit.replacement)
    #expect(!edit.source.text.utf8.elementsEqual(edit.replacement.utf8))
    #expect(Array(edit.source.text.utf8) == Array("caf\u{E9}".utf8))
    #expect(Array(edit.replacement.utf8) == Array("cafe\u{301}".utf8))
  }

  @Test("Proposals retain original snapshot and leave source unchanged")
  func sourceIsolation() async throws {
    let original = "class Original {}"
    let codebase = Codebase(root: .sources([
      "Sources/Model.swift": original,
    ]))
    let other = Codebase(root: .sources([
      "Sources/Model.swift": "class Other {}",
    ]))
    let violations = try await codebase.classes
      .violations("Rename declaration") { declaration in
        try declaration.nameSource.replacement(with: "Updated")
      }
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)
    let originalFile = try await codebase.files.only()
    let otherFile = try await other.files.only()

    #expect(edit.source.text == "Original")
    #expect(edit.source.file.text == original)
    #expect(try originalFile.source.text == original)
    #expect(try otherFile.source.text == "class Other {}")
  }
}
