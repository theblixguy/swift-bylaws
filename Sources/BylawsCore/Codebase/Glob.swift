// Glob uses a local matcher. The standard Regex type is not Sendable.

/// A glob pattern for including or excluding files.
///
/// Patterns support `*` (any characters within one path segment), `?`
/// (one character) and `**` (any number of path segments, including
/// none). Matching uses root-relative paths. Every pattern is valid.
public struct Glob: Sendable, Hashable, ExpressibleByStringLiteral {
  /// The pattern, as written.
  public let pattern: String

  private let segments: [Segment]

  /// Creates a glob from `pattern`.
  public init(_ pattern: String) {
    self.pattern = pattern
    segments = Self.parse(pattern)
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  /// Checks whether `relativePath` matches this pattern.
  public func matches(_ relativePath: String) -> Bool {
    matches(Path(relativePath))
  }

  /// Checks whether `path` matches this pattern.
  public func matches(_ path: Path) -> Bool {
    Self.match(segments, against: path.components)
  }

  /// Checks whether this pattern matches every path under `directory`.
  ///
  /// A pattern covers a directory when it ends in `**` and the preceding
  /// segments match the directory. File-tree walkers can skip a covered
  /// directory without visiting its contents.
  public func coversEverything(under directory: Path) -> Bool {
    guard case .anyDirectories = segments.last else { return false }
    return Self.match(Array(segments.dropLast()), against: directory.components)
  }

  package func canMatchDescendant(of directory: Path) -> Bool {
    var states = Self.statesAfterSkippingAnyDirectories(from: [0], in: segments)
    for component in directory.components {
      var next: Set<Int> = []
      for index in states where index < segments.count {
        switch segments[index] {
        case .anyDirectories:
          next.insert(index)
        case let .component(tokens)
          where Self.match(tokens, against: component):
          next.insert(index + 1)
        case .component:
          break
        }
      }
      states = Self.statesAfterSkippingAnyDirectories(from: next, in: segments)
      guard !states.isEmpty else { return false }
    }
    return states.contains { $0 < segments.count }
  }

  /// A root-relative path split into its components once, for matching
  /// against several patterns.
  public struct Path: Sendable {
    fileprivate let components: [[Unicode.Scalar]]

    /// Creates a path from `relativePath`.
    public init(_ relativePath: String) {
      components = Glob.components(of: relativePath)
    }
  }

  // Scalar copies avoid slow Character indexing on bridged NSString paths.
  private static func components(of path: String) -> [[Unicode.Scalar]] {
    var path = path
    path.makeContiguousUTF8()
    return path.unicodeScalars.split(separator: "/").map(Array.init)
  }
}

extension Glob {
  public static func == (lhs: Glob, rhs: Glob) -> Bool {
    lhs.pattern == rhs.pattern
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(pattern)
  }
}

extension Glob {
  private enum Segment: Sendable {
    case anyDirectories
    case component([Token])
  }

  private enum Token: Sendable {
    case literal(Unicode.Scalar)
    case anyRun
    case anyOne
  }

  private static func parse(_ pattern: String) -> [Segment] {
    components(of: pattern).map { component in
      if component == ["*", "*"] {
        .anyDirectories
      } else {
        .component(tokens(of: component))
      }
    }
  }

  private static func tokens(of component: [Unicode.Scalar]) -> [Token] {
    var tokens: [Token] = []
    for character in component {
      switch character {
      case "*":
        if case .anyRun = tokens.last { continue }
        tokens.append(.anyRun)
      case "?":
        tokens.append(.anyOne)
      default:
        tokens.append(.literal(character))
      }
    }
    return tokens
  }
}

// Iteration avoids exponential recursion for repeated stars.
extension Glob {
  private static func statesAfterSkippingAnyDirectories(
    from initial: Set<Int>,
    in segments: [Segment]
  ) -> Set<Int> {
    var states = initial
    var pending = Array(initial)
    var index = 0
    while index < pending.count {
      let state = pending[index]
      index += 1
      guard state < segments.count,
            case .anyDirectories = segments[state],
            states.insert(state + 1).inserted
      else { continue }
      pending.append(state + 1)
    }
    return states
  }

  private static func match(
    _ segments: [Segment],
    against components: [[Unicode.Scalar]]
  ) -> Bool {
    var componentIndex = 0
    var segmentIndex = 0
    var starSegmentIndex = -1
    var starComponentIndex = 0

    while componentIndex < components.count {
      if segmentIndex < segments.count,
         case let .component(tokens) = segments[segmentIndex],
         match(tokens, against: components[componentIndex])
      {
        segmentIndex += 1
        componentIndex += 1
      } else if segmentIndex < segments.count,
                case .anyDirectories = segments[segmentIndex]
      {
        starSegmentIndex = segmentIndex
        starComponentIndex = componentIndex
        segmentIndex += 1
      } else if starSegmentIndex >= 0 {
        segmentIndex = starSegmentIndex + 1
        starComponentIndex += 1
        componentIndex = starComponentIndex
      } else {
        return false
      }
    }
    while segmentIndex < segments.count,
          case .anyDirectories = segments[segmentIndex]
    {
      segmentIndex += 1
    }
    return segmentIndex == segments.count
  }

  private static func match(
    _ tokens: [Token],
    against text: [Unicode.Scalar]
  ) -> Bool {
    var textIndex = 0
    var tokenIndex = 0
    var starTokenIndex = -1
    var starTextIndex = 0

    while textIndex < text.count {
      if tokenIndex < tokens.count,
         matchesOneCharacter(tokens[tokenIndex], text[textIndex])
      {
        tokenIndex += 1
        textIndex += 1
      } else if tokenIndex < tokens.count, case .anyRun = tokens[tokenIndex] {
        starTokenIndex = tokenIndex
        starTextIndex = textIndex
        tokenIndex += 1
      } else if starTokenIndex >= 0 {
        tokenIndex = starTokenIndex + 1
        starTextIndex += 1
        textIndex = starTextIndex
      } else {
        return false
      }
    }
    while tokenIndex < tokens.count, case .anyRun = tokens[tokenIndex] {
      tokenIndex += 1
    }
    return tokenIndex == tokens.count
  }

  private static func matchesOneCharacter(
    _ token: Token,
    _ character: Unicode.Scalar
  ) -> Bool {
    switch token {
    case let .literal(literal): literal == character
    case .anyOne: true
    case .anyRun: false
    }
  }
}
