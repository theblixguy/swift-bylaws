package enum NameFilter: Sendable, Hashable {
  case named([String])
  case suffixed([String])
  case prefixed([String])
  case excluding([String])

  func matches(_ name: String) -> Bool {
    switch self {
    case let .named(names): names.contains(name)
    case let .suffixed(suffixes): suffixes.contains { name.hasSuffix($0) }
    case let .prefixed(prefixes): prefixes.contains { name.hasPrefix($0) }
    case let .excluding(names): !names.contains(name)
    }
  }

  var description: String {
    switch self {
    case let .named(names): "named \(names.quotedList)"
    case let .suffixed(suffixes): "suffixed \(suffixes.quotedList)"
    case let .prefixed(prefixes): "prefixed \(prefixes.quotedList)"
    case let .excluding(names): "excluding \(names.quotedList)"
    }
  }
}
