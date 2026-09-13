extension Matcher {
  /// Creates a matcher that passes when the selected Boolean property is true.
  public init(_ keyPath: any KeyPath<Subject, Bool> & Sendable) {
    self.init("have \(propertyName(of: keyPath)) be true") {
      $0[keyPath: keyPath]
    }
  }
}

/// Matches declarations whose `keyPath` value equals `value`.
public func == <Subject, Value: Equatable & Sendable>(
  keyPath: any KeyPath<Subject, Value> & Sendable,
  value: Value
) -> Matcher<Subject> {
  Matcher(
    "have \(article(for: keyPath)) \(propertyName(of: keyPath)) of \(rendered(value))"
  ) {
    $0[keyPath: keyPath] == value
  }
}

/// Matches declarations whose `keyPath` value differs from `value`.
public func != <Subject, Value: Equatable & Sendable>(
  keyPath: any KeyPath<Subject, Value> & Sendable,
  value: Value
) -> Matcher<Subject> {
  !(keyPath == value)
}

/// Matches declarations whose `keyPath` value is at most `value`.
public func <= <Subject, Value: Comparable & Sendable>(
  keyPath: any KeyPath<Subject, Value> & Sendable,
  value: Value
) -> Matcher<Subject> {
  Matcher(
    "have \(article(for: keyPath)) \(propertyName(of: keyPath)) of at most \(rendered(value))"
  ) {
    $0[keyPath: keyPath] <= value
  }
}

/// Matches declarations whose `keyPath` value is at least `value`.
public func >= <Subject, Value: Comparable & Sendable>(
  keyPath: any KeyPath<Subject, Value> & Sendable,
  value: Value
) -> Matcher<Subject> {
  Matcher(
    "have \(article(for: keyPath)) \(propertyName(of: keyPath)) of at least \(rendered(value))"
  ) {
    $0[keyPath: keyPath] >= value
  }
}

/// Matches declarations whose `keyPath` value is under `value`.
public func < <Subject, Value: Comparable & Sendable>(
  keyPath: any KeyPath<Subject, Value> & Sendable,
  value: Value
) -> Matcher<Subject> {
  Matcher(
    "have \(article(for: keyPath)) \(propertyName(of: keyPath)) under \(rendered(value))"
  ) {
    $0[keyPath: keyPath] < value
  }
}

/// Matches declarations whose `keyPath` value is over `value`.
public func > <Subject, Value: Comparable & Sendable>(
  keyPath: any KeyPath<Subject, Value> & Sendable,
  value: Value
) -> Matcher<Subject> {
  Matcher(
    "have \(article(for: keyPath)) \(propertyName(of: keyPath)) over \(rendered(value))"
  ) {
    $0[keyPath: keyPath] > value
  }
}

private func article(for keyPath: AnyKeyPath) -> String {
  let name = propertyName(of: keyPath)
  return name.first.map { "aeiou".contains($0) } == true ? "an" : "a"
}

func propertyName(of keyPath: AnyKeyPath) -> String {
  let description = String(describing: keyPath)
  guard let name = description.split(separator: ".").last,
        !name.contains(" "), !name.contains("<")
  else { return "value" }
  return String(name)
}

private func rendered(_ value: Any) -> String {
  if let string = value as? String {
    return "'\(string)'"
  }
  let mirror = Mirror(reflecting: value)
  if mirror.displayStyle == .optional {
    guard let child = mirror.children.first else { return "nil" }
    return rendered(child.value)
  }
  return String(describing: value)
}
