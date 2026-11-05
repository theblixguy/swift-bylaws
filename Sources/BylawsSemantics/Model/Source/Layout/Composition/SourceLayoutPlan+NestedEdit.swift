extension SourceLayoutPlan {
  package struct NestedEdit: Sendable, Hashable, Codable {
    package enum Ownership: String, Sendable, Codable {
      case independent
      case withLayout
    }

    package let edit: CapturedEdit
    package let ownership: Ownership

    package var range: Range<Int> { edit.range }
    package var layout: SourceLayoutPlan? { edit.layout }

    package init(
      range: Range<Int>, replacement: String, layout: SourceLayoutPlan? = nil,
      ownership: Ownership = .independent
    ) {
      edit = CapturedEdit(
        range: range,
        replacement: replacement,
        layout: layout
      )
      self.ownership = ownership
    }

    package init(_ edit: SourceFix.Edit, ownership: Ownership = .independent) {
      self.edit = CapturedEdit(edit)
      self.ownership = ownership
    }

    package func resolve(snapshot: SourceSnapshot) throws -> SourceFix.Edit {
      try edit.resolve(snapshot: snapshot)
    }
  }
}
