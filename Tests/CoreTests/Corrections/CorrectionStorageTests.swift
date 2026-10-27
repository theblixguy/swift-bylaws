import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Correction storage")
struct CorrectionStorageTests {
  @Test("Absent and all-nil corrections share storage semantics")
  func noCorrections() throws {
    let absent = Violations(
      rule: "be final",
      offenders: [1, 2],
      checkedCount: 3
    )
    let explicit = Violations(
      rule: "be final", offenders: [1, 2], checkedCount: 3,
      witnesses: [nil, nil], fixes: [nil, nil]
    )

    #expect(absent.proposedFixes == nil)
    #expect(explicit.proposedFixes == nil)
    #expect(absent.fixes == [nil, nil])
    #expect(absent == explicit)
    #expect(Set([absent, explicit]).count == 1)
    #expect(absent.filteringOffenders { $0 == 2 }.proposedFixes == nil)
    let object = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(explicit)
    ) as? [String: Any])
    #expect(object["fixes"] == nil)
  }

  @Test(
    "Public decoding normalises absent null and all-nil corrections",
    arguments: [
      "", ",\"fixes\":null", ",\"fixes\":[null,null]",
    ]
  )
  func decoding(field: String) throws {
    let data = Data(
      "{\"rule\":\"be final\",\"offenders\":[1,2],\"checkedCount\":3\(field)}"
        .utf8
    )
    let result = try JSONDecoder().decode(Violations<Int>.self, from: data)

    #expect(result.proposedFixes == nil)
    #expect(result.offenders == [1, 2])
    #expect(result.checkedCount == 3)
    #expect(result.fixes == [nil, nil])
  }

  @Test("Public decoding rejects correction count mismatch", arguments: [
    "[]", "[null]", "[null,null,null]",
  ])
  func malformedCount(fixes: String) {
    let data = Data(
      "{\"rule\":\"be final\",\"offenders\":[1,2],\"checkedCount\":2,\"fixes\":\(fixes)}"
        .utf8
    )

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Violations<Int>.self, from: data)
    }
  }

  @Test("Filtering and transport retain mixed correction indices")
  func mixedCorrections() throws {
    let fix = try correction()
    let original = Violations(
      rule: "be final", offenders: [1, 2, 3], checkedCount: 4,
      witnesses: [nil, nil, nil], fixes: [nil, fix, nil]
    )
    let filtered = original.filteringOffenders { $0 > 1 }
    let withoutFix = original.filteringOffenders { $0 != 2 }
    let decoded = try JSONDecoder().decode(
      Violations<Int>.self, from: JSONEncoder().encode(original)
    )

    #expect(filtered.offenders == [2, 3])
    #expect(filtered.fixes == [fix, nil])
    #expect(filtered.fixes[0]?.edits.first?.replacement == "New")
    #expect(withoutFix.offenders == [1, 3])
    #expect(withoutFix.proposedFixes == nil)
    #expect(decoded == original)
    #expect(decoded.fixes == [nil, fix, nil])
  }

  @Test("Combined findings allocate correction slots only for mixed fixes")
  func combinedFindings() throws {
    let offenders = ["first", "second", "third"].map {
      Offender(description: $0, location: .start(of: "/virtual/App.swift"))
    }
    let plain = Violations(
      rule: "be final", offenders: [offenders[0]], checkedCount: 1
    )
    let fix = try correction()
    let corrected = Violations(
      rule: "use name", offenders: Array(offenders[1...]), checkedCount: 2,
      witnesses: [nil, nil], fixes: [nil, fix]
    )
    let unfixed = Rule.Findings(checks: [plain, plain]).violations
    let combined = Rule.Findings(checks: [plain, corrected]).violations

    #expect(unfixed.proposedFixes == nil)
    #expect(unfixed.fixes == [nil, nil])
    #expect(combined.offenders.map(\.description) == [
      "first",
      "second",
      "third",
    ])
    #expect(combined.checkedCount == 3)
    #expect(combined.fixes == [nil, nil, fix])
  }

  @Test("Erasure preserves absent and mixed correction storage")
  func erasure() throws {
    let file = try FileCollector.collect(
      source: "class Old {}", path: "/virtual/App.swift"
    )
    let plain = Violations(
      rule: "be final",
      offenders: file.classes,
      checkedCount: 1
    )
    let corrected = Violations(
      rule: "be final", offenders: file.classes, checkedCount: 1,
      witnesses: [nil], fixes: [try correction()]
    )

    #expect(plain.erased().proposedFixes == nil)
    let fix = try #require(corrected.erased().fixes.first ?? nil)
    #expect(fix.edits.first?.replacement == "New")
  }

  private func correction() throws -> SourceFix {
    let file = try FileCollector.collect(
      source: "class Old {}", path: "/virtual/App.swift"
    )
    return try SourceFix(edits: [file.classes.only().nameSource
        .replacement(with: "New")])
  }
}
