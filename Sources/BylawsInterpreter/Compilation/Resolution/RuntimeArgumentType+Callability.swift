extension SupportedAPI.RuntimeArgumentType {
  var isCallable: Bool {
    switch self {
    case .collectionCallable, .callable, .dictionaryValueCallable: true
    default: false
    }
  }
}
