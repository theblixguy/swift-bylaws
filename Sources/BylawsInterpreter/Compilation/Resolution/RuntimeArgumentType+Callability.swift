extension SupportedAPI.RuntimeArgumentType {
  var isCallable: Bool {
    switch self {
    case .collectionCallable, .collectionComparator, .callable,
         .dictionaryValueCallable: true
    default: false
    }
  }
}
