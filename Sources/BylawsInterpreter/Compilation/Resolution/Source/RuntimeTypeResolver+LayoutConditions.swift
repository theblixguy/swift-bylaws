import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveLayoutCondition(
    values: [(String?, RuntimeExpression)], at location: DeclarationLocation
  ) -> RuntimeType {
    guard values.count == 1, values[0].0 == nil else {
      diagnose("maximumLineLength takes one Int range", at: location)
      values.forEach { _ = resolve($0.1) }
      return .sourceLayoutCondition
    }
    switch resolve(values[0].1) {
    case .integerRange, .integerClosedRange, .integerRangeFrom,
         .integerRangeThrough, .integerRangeUpTo: break
    default: diagnose("maximumLineLength takes one Int range", at: location)
    }
    return .sourceLayoutCondition
  }
}
