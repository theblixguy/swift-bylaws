import BylawsSemantics

extension RuntimeValue {
  func capturedReplacement(at location: DeclarationLocation)
    throws(RuntimeError) -> SourceReplacement
  {
    if case let .sourceReplacement(replacement) = self { return replacement }
    return SourceReplacement(source: try sourceProvider(at: location))
  }

  func replacementContent(at location: DeclarationLocation)
    throws(RuntimeError) -> SourceReplacement
  {
    switch self {
    case let .sourceReplacement(replacement): return replacement
    case let .sourceScope(scope): return scope.replacement
    default:
      if let sources = sequenceElements {
        return SourceReplacement(combining: try sources.map {
          value throws(RuntimeError) in
          SourceReplacement(source: try value.sourceProvider(at: location))
        })
      }
      return SourceReplacement(source: try sourceProvider(at: location))
    }
  }
}

extension SupportedAPI.RuntimeType {
  var supportsReplacement: Bool {
    providesSource || sequenceElement?.providesSource == true
      || self == .sourceReplacement || self == .sourceScope
  }
}
