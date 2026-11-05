package struct SourceListMutationPlan: Sendable, Hashable, Codable {
  enum Operation: Sendable, Hashable, Codable {
    case insert(String, at: SourceListPosition)
    case remove(Range<Int>)

    static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
      case let (
        .insert(left, at: leftPosition),
        .insert(right, at: rightPosition)
      ):
        leftPosition == rightPosition && left.utf8.elementsEqual(right.utf8)
      case let (.remove(left), .remove(right)): left == right
      default: false
      }
    }

    func hash(into hasher: inout Hasher) {
      switch self {
      case let .insert(text, position):
        hasher.combine(0)
        hasher.combine(position)
        for byte in text.utf8 { hasher.combine(byte) }
      case let .remove(range):
        hasher.combine(1)
        hasher.combine(range)
      }
    }
  }

  struct Mutation: Sendable, Hashable, Codable {
    let owner: Range<Int>
    let kind: SourceListContext.Kind
    let operations: [Operation]

    func resolve(snapshot: SourceSnapshot) throws -> SourceListSyntax {
      try SourceListContext(
        owner: SourceSlice(snapshot: snapshot, range: owner), kind: kind
      ).resolve()
    }

    func edits(snapshot: SourceSnapshot) throws -> [SourceFix.Edit] {
      let list = try resolve(snapshot: snapshot)
      return try operations.flatMap { operation in
        let correction = switch operation {
        case let .insert(text, position):
          try SourceListEditing.insert(text, into: list, at: position)
        case let .remove(range):
          try SourceListEditing.remove(
            SourceSlice(snapshot: snapshot, range: range), from: list
          )
        }
        guard let fix = correction.fix else { throw SourceError.syntaxMismatch }
        return fix.edits
      }
    }
  }

  let mutations: [Mutation]
  let formatsElements: Bool

  static func capture(
    _ correction: SourceCorrection, list: SourceListSyntax, operation: Operation
  ) throws -> SourceCorrection {
    guard let fix = correction.fix else { return correction }
    let replacement = try list.source.replacement(applying: fix.edits)
      .replacement
    let elements = try list.slices().map(\.range)
    let plan = SourceLayoutPlan(
      elements: elements,
      targetRange: list.source.range,
      mode: .listMutation(Self(
        mutations: [.init(
          owner: list.context.owner.range, kind: list.context.kind,
          operations: [operation]
        )], formatsElements: false
      ), layout: nil)
    )
    return SourceCorrection(edits: [SourceFix.Edit(
      source: list.source, replacement: replacement, layout: plan
    )])
  }

  func validate(target: SourceSlice, plan: SourceLayoutPlan) throws {
    guard !mutations.isEmpty,
          plan.formatting?.trimmed != true,
          plan.formatting?.allowsPartialList != true,
          !formatsElements || mutations.count == 1
    else { throw SourceError.syntaxMismatch }
    if mutations.count > 1 {
      guard mutations.count == 2,
            mutations[0].owner == mutations[1].owner,
            Set(mutations.map(\.kind)) == [.attributes, .modifiers]
      else { throw SourceError.syntaxMismatch }
    }
    var bounds: Range<Int>?
    var ranges: [Range<Int>] = []
    for mutation in mutations {
      let list = try mutation.resolve(snapshot: target.snapshot)
      guard mutation.owner == list.context.owner.range,
            !mutation.operations.isEmpty
      else { throw SourceError.syntaxMismatch }
      _ = try mutation.edits(snapshot: target.snapshot)
      ranges += try list.slices().map(\.range)
      bounds = bounds.map {
        min($0.lowerBound, list.source.range.lowerBound)
          ..< max($0.upperBound, list.source.range.upperBound)
      } ?? list.source.range
    }
    guard bounds == target.range, ranges.count == plan.elements.count
    else { throw SourceError.syntaxMismatch }
    if formatsElements {
      let list = try mutations[0].resolve(snapshot: target.snapshot)
      let indices = try plan.elements.map {
        try list.index(of: SourceSlice(snapshot: target.snapshot, range: $0))
      }
      guard Set(indices) == Set(list.elements.indices)
      else { throw SourceError.syntaxMismatch }
    } else {
      guard Set(ranges) == Set(plan.elements), plan.formatting == nil
      else { throw SourceError.syntaxMismatch }
    }
  }
}
