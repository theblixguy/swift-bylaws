import BylawsSemantics
import Foundation
import Testing

@Suite("Captured layout transport")
struct SourceLayoutPlanCodingTests {
  @Test("Edits without layout metadata retain their transport format")
  func plainEdit() throws {
    let data = Data(
      #"{"source":{"snapshot":{"filePath":"/project/Screen.swift","text":"class Screen {}","swiftLanguageMode":"6"},"range":[6,12]},"replacement":"Updated"}"#
        .utf8
    )
    let decoded = try JSONDecoder().decode(SourceFix.Edit.self, from: data)
    let payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(decoded)
    ) as? [String: Any])

    #expect(decoded.source.text == "Screen")
    #expect(decoded.replacement == "Updated")
    #expect(decoded.layout == nil)
    #expect(payload["layout"] == nil)
  }

  @Test("Standalone edits retain layout policy and exact source")
  func standaloneEdit() throws {
    let edit = try attributeEdit()
    let decoded = try JSONDecoder().decode(
      SourceFix.Edit.self, from: JSONEncoder().encode(edit)
    )
    let plan = try #require(decoded.layout)
    let layout = try plan.thaw(snapshot: decoded.source.snapshot)
    let elements = try plan.elements.map {
      try SourceSlice(snapshot: decoded.source.snapshot, range: $0)
    }
    let rendered = try SourceLayoutReplacement.make(
      elements: elements, layout: layout
    )

    #expect(decoded == edit)
    #expect(decoded.source.text == "@MainActor\n@Observable ")
    #expect(decoded.replacement == "@Observable @MainActor\n")
    #expect(rendered.replacement == "@Observable @MainActor\n")
  }

  @Test("Standalone decoding rejects a forged layout preview")
  func forgedPreview() throws {
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(attributeEdit())
    ) as? [String: Any])
    payload["replacement"] = "@MainActor\n"
    let data = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SourceFix.Edit.self, from: data)
    }
  }

  @Test("Trimmed layouts reject expanded edit targets")
  func expandedGroupedTarget() throws {
    let file = try FileCollector.collect(
      source: "struct Panel {\n  func keep() {}\n}",
      path: "/project/Panel.swift"
    )
    let declaration = try #require(file.syntaxNodes(of: .structDeclaration)
      .first)
    let fix = try declaration.members.replacement {
      Group(where: { _ in true })
    }
    let edit = try #require(fix.layoutCandidates.first)
    let plan = try #require(edit.layout)
    let encoded = try JSONEncoder().encode(edit)
    let restored = try JSONDecoder().decode(SourceFix.Edit.self, from: encoded)
    #expect(restored.source.text == "func keep() {}")
    #expect(restored.replacement == "func keep() {}")
    try #require(plan.trimmed)
    let expanded = try declaration.source
    let forgedPlan = SourceLayoutPlan(
      elements: plan.elements, node: plan.node,
      allowsPartialList: plan.allowsPartialList,
      baseIndentation: plan.baseIndentation, targetRange: expanded.range,
      trimmed: true, lineWidthLimit: plan.lineWidthLimit, nested: plan.nested
    )
    var payload = try #require(JSONSerialization.jsonObject(with: encoded)
      as? [String: Any])
    payload["source"] = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(expanded)
    )
    payload["layout"] = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(forgedPlan)
    )
    payload["replacement"] = "func keep() {}"
    let data = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: SourceError.syntaxMismatch) {
      try JSONDecoder().decode(SourceFix.Edit.self, from: data)
    }
  }

  @Test("Equal previews retain different layout policies")
  func policyIdentity() throws {
    let edit = try attributeEdit()
    let original = try #require(edit.layout)
    let edits = [80, 120].map { width in
      SourceFix.Edit(
        source: edit.source, replacement: edit.replacement,
        layout: SourceLayoutPlan(
          elements: original.elements,
          node: .wrap(width: width, original.node),
          targetRange: original.targetRange
        )
      )
    }

    #expect(edits[0].replacement == edits[1].replacement)
    #expect(edits[0] != edits[1])
    #expect(Set(edits).count == 2)
    let decoded = try JSONDecoder().decode(
      [SourceFix.Edit].self, from: JSONEncoder().encode(edits)
    )
    #expect(Set(decoded).count == 2)
  }

  @Test("Embedded edits retain their own layout policy")
  func embeddedLayout() throws {
    let inner = try attributeEdit()
    let file = try FileCollector.collect(
      source: inner.source.file.text, path: inner.source.filePath
    )
    let layout = SourceLayout { inner }
    let replacement = try file.classes.replacement { layout }
    let plan = try SourceLayoutPlan(
      elements: file.classes.map { try $0.source.range },
      node: SourceLayoutPlan.freeze(
        layout,
        snapshot: replacement.source.snapshot
      ),
      targetRange: replacement.source.range
    )
    let edit = SourceFix.Edit(
      source: replacement.source, replacement: replacement.replacement,
      layout: plan
    )
    let decoded = try JSONDecoder().decode(
      SourceFix.Edit.self, from: JSONEncoder().encode(edit)
    )
    let restored = try #require(decoded.layout)
    let thawed = try restored.thaw(snapshot: decoded.source.snapshot)
    let nested = try #require(thawed.edits.first)

    #expect(nested.layout == inner.layout)
    #expect(nested.source.text == "@MainActor\n@Observable ")
    #expect(decoded.replacement == "@Observable @MainActor\nclass Screen {}")
  }

  @Test("Captured edits compare replacement bytes")
  func replacementBytes() {
    let first = SourceLayoutPlan.CapturedEdit(
      range: 0..<0, replacement: "caf\u{e9}"
    )
    let second = SourceLayoutPlan.CapturedEdit(
      range: 0..<0, replacement: "cafe\u{301}"
    )

    #expect(first.replacement == second.replacement)
    #expect(first != second)
    #expect(Set([first, second]).count == 2)
  }

  @Test("Freezing rejects source from another snapshot")
  func foreignSnapshot() throws {
    let first = try FileCollector.collect(
      source: "class First {}", path: "/project/First.swift"
    )
    let second = try FileCollector.collect(
      source: "class Second {}", path: "/project/Second.swift"
    )
    let layout = SourceLayout { second.classes }

    #expect(throws: SourceError.differentSnapshots) {
      try SourceLayoutPlan.freeze(layout, snapshot: first.source.snapshot)
    }
  }

  @Test(
    "Decoded plans reject source ranges outside their target",
    arguments: RangePart.allCases
  )
  func foreignRange(part: RangePart) throws {
    let edit = try attributeEdit()
    let original = try #require(edit.layout)
    let outside = edit.source.range
      .upperBound..<(edit.source.range.upperBound + 1)
    let plan = SourceLayoutPlan(
      elements: part == .element ? [outside] : original.elements,
      node: part == .node ? .source(outside) : original.node,
      targetRange: original.targetRange,
      nested: part == .nested ? [.init(range: outside, replacement: "")] : []
    )

    #expect(throws: SourceError.rangeOutOfBounds) {
      try decode(edit, replacingPlan: plan)
    }
  }

  @Test("Decoded plans reject nested edits outside retained elements")
  func unownedNestedEdit() throws {
    let edit = try attributeEdit()
    let original = try #require(edit.layout)
    let plan = SourceLayoutPlan(
      elements: original.elements, node: original.node,
      targetRange: original.targetRange,
      nested: [.init(range: 10..<11, replacement: "\n\n")]
    )

    #expect(throws: (any Error).self) {
      try decode(edit, replacingPlan: plan)
    }
  }

  @Test("Decoded plans reject ranges within UTF-8 scalars")
  func scalarBoundary() throws {
    let source = "@Label(\"👋\") class Screen {}"
    let file = try FileCollector.collect(
      source: source,
      path: "/project/Screen.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let edit = try attributes.replacement { attributes }
    let plan = SourceLayoutPlan(
      elements: try attributes.map { try $0.source.range },
      node: .source(9..<10), targetRange: edit.source.range
    )

    #expect(throws: SourceError.rangeOutOfBounds) {
      try decode(edit, replacingPlan: plan)
    }
  }

  @Test("Decoded plans retain the edit target", arguments: [false, true])
  func targetRange(nested: Bool) throws {
    let edit = try attributeEdit()
    let original = try #require(edit.layout)
    let wrong = SourceLayoutPlan(
      elements: original.elements, node: original.node,
      targetRange: 0..<1
    )
    let plan = if nested {
      SourceLayoutPlan(
        elements: original.elements, node: original.node,
        targetRange: original.targetRange,
        nested: [.init(
          range: original.targetRange, replacement: edit.replacement,
          layout: wrong
        )]
      )
    } else {
      wrong
    }

    #expect(throws: SourceError.syntaxMismatch) {
      try decode(edit, replacingPlan: plan)
    }
  }

  @Test("Decoded plans reject nonpositive widths", arguments: [0, -1])
  func widthLimit(width: Int) throws {
    let edit = try attributeEdit()
    let original = try #require(edit.layout)
    let plan = SourceLayoutPlan(
      elements: original.elements, node: original.node,
      targetRange: original.targetRange, lineWidthLimit: width
    )

    #expect(throws: SourceLayoutError.widthMustBePositive) {
      try decode(edit, replacingPlan: plan)
    }
  }

  enum RangePart: CaseIterable {
    case element, node, nested
  }

  private func attributeEdit() throws -> SourceFix.Edit {
    let file = try FileCollector.collect(
      source: "@MainActor\n@Observable class Screen {}",
      path: "/project/Screen.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let layout = SourceLayout { Line { attributes.reversed() } }
    let edit = try attributes.replacement { layout }
    let plan = try SourceLayoutPlan(
      elements: attributes.map { try $0.source.range },
      node: SourceLayoutPlan.freeze(layout, snapshot: edit.source.snapshot),
      targetRange: edit.source.range
    )
    return SourceFix.Edit(
      source: edit.source, replacement: edit.replacement, layout: plan
    )
  }

  private func decode(
    _ edit: SourceFix.Edit, replacingPlan plan: SourceLayoutPlan
  ) throws -> SourceFix.Edit {
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(edit)
    ) as? [String: Any])
    payload["layout"] = try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(plan)
    )
    return try JSONDecoder().decode(
      SourceFix.Edit.self,
      from: JSONSerialization.data(withJSONObject: payload)
    )
  }
}
