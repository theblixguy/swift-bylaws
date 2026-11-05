import BylawsSemantics

extension RuntimeValue {
  func correctionEdits(at location: DeclarationLocation) throws(RuntimeError)
    -> [SourceFix.Edit]
  {
    switch self {
    case let .sourceFix(fix): return fix.edits + fix.layoutCandidates
    case let .sourceEdit(edit): return [edit]
    case let .array(values):
      var edits: [SourceFix.Edit] = []
      for value in values {
        edits.append(contentsOf: try value.correctionEdits(at: location))
      }
      return edits
    default: throw RuntimeError(
        message: "Correction takes source edits, fixes or edit arrays",
        location: location
      )
    }
  }

  func correction(at location: DeclarationLocation) throws(RuntimeError)
    -> SourceCorrection
  {
    switch self {
    case let .sourceCorrection(value), let .layoutCorrection(value): value
    case let .sourceFix(value): value.correction
    case let .sourceEdit(value): value.correction
    case let .array(values):
      SourceCorrection(combining: try values.map { value throws(RuntimeError) in
        try value.correction(at: location)
      })
    default:
      throw RuntimeError(
        message: RuntimeBuilder.correction.argumentRequirement,
        location: location
      )
    }
  }
}
