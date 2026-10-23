extension SupportedAPI.RuntimeResult {
  func resolve(
    receiver: SupportedAPI.RuntimeType,
    closureResult: SupportedAPI.RuntimeType?,
    argumentLabels: [String?] = []
  ) -> SupportedAPI.RuntimeType {
    switch self {
    case .fixOffender:
      guard case let .fixContext(subject) = receiver else { return .unknown }
      return subject.map(SupportedAPI.RuntimeType.model) ?? .unknown
    case .mappedDictionary:
      guard case let .dictionary(key, _) = receiver else { return .unknown }
      return .dictionary(key: key, value: closureResult ?? .unknown)
    case let .fixed(type): return type
    case .receiver: return receiver
    case .orderedCollection: return .array(receiver.collectionElement)
    case .slicedCollection: return .arraySlice(receiver.collectionElement)
    case .collection:
      switch receiver {
      case .selection, .arraySlice: return .array(receiver.collectionElement)
      default: return receiver
      }
    case .collectionElement:
      return receiver.collectionElement
    case .optionalCollectionElement:
      return .optional(receiver.collectionElement)
    case .manifestListKnownValues, .manifestListConditionalValues,
         .manifestListPossibleValues:
      return .array(receiver.collectionElement)
    case .manifestListValues:
      return .optional(.array(receiver.collectionElement))
    case .closureResult: return .array(closureResult ?? .unknown)
    case .optionalClosureResult:
      if case let .optional(wrapped) = closureResult { return .array(wrapped) }
      return .array(closureResult ?? .unknown)
    case .flattenedClosureResult:
      if let element = closureResult?.sequenceElement { return .array(element) }
      return .array(.unknown)
    case .syntaxClosureResult:
      let result = closureResult ?? .unknown
      return argumentLabels.contains(.of)
        ? .optional(result) : result
    case .violationsForSelection:
      return .violations(receiver.collectionElement.modelType)
    case .violationOffenders:
      guard case let .violations(subject) = receiver else { return .unknown }
      return .array(subject.map(SupportedAPI.RuntimeType.model) ?? .unknown)
    }
  }
}
