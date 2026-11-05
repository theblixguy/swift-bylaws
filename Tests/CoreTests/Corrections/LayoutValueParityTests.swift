import Bylaws
import Testing

@Suite("Layout value contracts")
struct LayoutValueParityTests {
  @Test("Stored content renders source and component layouts")
  func storedComponents() throws {
    let file = try FileCollector.collect(
      source: "@A @B class Item {}",
      path: "/virtual/Item.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let component = Line(attributes.reversed())
    let erased: any SourceLayoutProviding = component
    let descriptions: [LayoutContent<Attribute>] = [
      .layout(source: component.layout),
      .layout(component.layout),
      .layout(component),
      .layout(erased),
    ]

    for description in descriptions {
      let operation = try Layout(attributes, layout: description)
      let fix = try #require(operation.correction.fix)

      #expect(try file.source.replacement(applying: fix.edits)
        .replacement == "@B @A\nclass Item {}")
    }
  }

  @Test(
    "Explicit layout content stays distinct from separators",
    arguments: [false, true]
  )
  func contentCases(explicit: Bool) throws {
    let file = try FileCollector.collect(
      source: "@A @B class Item {}",
      path: "/virtual/Item.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let content: LayoutContent<Attribute> = .sequence([
      .group(Group { _ in true }),
      explicit ? .layout(.newline) : .separator(.newline),
    ])

    if explicit {
      #expect(throws: SourceListLayoutError.mixedContent) {
        _ = try Layout(attributes, layout: content)
      }
    } else {
      let operation = try Layout(attributes, layout: content)
      #expect(operation.correction.outcome == .satisfied)
      #expect(operation.correction.fix?.edits.isEmpty == true)
    }
  }

  @Test(
    "Layouts take edit arrays and nested correction arrays",
    arguments: [false, true]
  )
  func correctionArrays(nested: Bool) throws {
    let file = try FileCollector.collect(
      source: "@A @B class Item {}",
      path: "/virtual/Item.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let edits = [
      try attributes[0].source.replacement(with: "@C"),
      try attributes[1].source.replacement(with: "@D"),
    ]
    let changes = [edits.map { SourceCorrection(edits: [$0]) }]
    let layout = if nested {
      SourceLayout { changes }
    } else {
      SourceLayout { edits }
    }
    let operation = try Layout(attributes, layout: layout)
    let fix = try #require(operation.correction.fix)

    #expect(try file.source.replacement(applying: fix.edits)
      .replacement == "@C @D class Item {}")
  }
}
