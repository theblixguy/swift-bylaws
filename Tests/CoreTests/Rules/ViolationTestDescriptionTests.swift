import Bylaws
import Testing

@Suite("Swift Testing violation descriptions")
struct ViolationTestDescriptionTests {
  @Test(
    "Descriptions show rule results and declaration locations",
    arguments: [false, true]
  )
  func description(passing: Bool) throws {
    let file = try FileCollector.collect(
      source: "class Open {}", path: "/virtual/Model.swift"
    )
    let result = Violations<NominalType>(
      rule: "be final",
      offenders: passing ? [] : file.classes.map(NominalType.class),
      checkedCount: 1
    )
    let expected = if passing {
      "no violations of 'be final' (1 checked)"
    } else {
      "1 violation of 'be final':\n  - class Open (Model.swift:1)"
    }

    #expect(String(describingForTest: result) == expected)
    let comment: Comment = "\(result)"
    #expect(comment.rawValue == expected)
  }
}
