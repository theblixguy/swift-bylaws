import BylawsPaths
public import BylawsSemantics
package import Foundation

/// The results of a codebase query.
///
/// Narrow a selection with filters such as `where(_:)`, `named(_:)` and
/// `under(_:)`, then check it with `Violations(of:in:)`. A selection keeps
/// a description of the query that produced it and failure messages render
/// that description.
public struct Selection<Element: Sendable>: Sendable {
  @usableFromInline
  package let storage: SelectionStorage<Element>

  var elements: [Element] { storage.elements }

  /// The description of the query that produced this selection.
  public let queryDescription: String

  package let rootPath: String

  package init(
    elements: [Element],
    queryDescription: String,
    rootPath: String
  ) {
    storage = SelectionStorage(elements)
    self.queryDescription = queryDescription
    self.rootPath = rootPath
  }

  package init(
    storage: SelectionStorage<Element>,
    queryDescription: String,
    rootPath: String
  ) {
    self.storage = storage
    self.queryDescription = queryDescription
    self.rootPath = rootPath
  }

  func narrowed(to elements: [Element], appending clause: String) -> Selection {
    let description = "\(queryDescription) \(clause)"
    QueryInspection.record(
      query: description,
      selected: elements.compactMap(SelectionInspection.Element.init),
      previous: self.elements.compactMap(SelectionInspection.Element.init)
    )
    return Selection(
      elements: elements,
      queryDescription: description,
      rootPath: rootPath
    )
  }

  /// Returns the elements for which `keyPath` is true.
  public func `where`(_ keyPath: any KeyPath<Element, Bool> & Sendable)
    -> Selection
  {
    narrowed(
      to: elements.filter { $0[keyPath: keyPath] },
      appending: "where \(propertyName(of: keyPath)) is true"
    )
  }

  /// Returns the elements matching `matcher`.
  public func `where`(_ matcher: Matcher<Element>) -> Selection {
    narrowed(
      to: elements.filter { matcher($0) },
      appending: "that \(matcher.requirementDescription)"
    )
  }
}

@usableFromInline
package final class SelectionStorage<Element: Sendable>: Sendable {
  @usableFromInline
  package let elements: [Element]

  package let identity: UUID

  package init(_ elements: [Element], identity: UUID = UUID()) {
    self.identity = identity
    self.elements = elements
  }
}

extension Selection: RandomAccessCollection {
  @inlinable
  public var startIndex: Int { storage.elements.startIndex }

  @inlinable
  public var endIndex: Int { storage.elements.endIndex }

  @inlinable
  public subscript(position: Int) -> Element { storage.elements[position] }
}

extension Selection where Element: Named {
  /// Returns the elements named exactly one of `names`.
  public func named(_ names: String...) -> Selection {
    named(names)
  }

  /// Returns the elements named exactly one of `names`.
  public func named(_ names: [String]) -> Selection {
    narrowed(
      to: elements.filter { names.contains($0.name) },
      appending: "named \(names.quotedList)"
    )
  }

  /// Returns the elements whose name ends with one of `suffixes`.
  public func suffixed(_ suffixes: String...) -> Selection {
    suffixed(suffixes)
  }

  /// Returns the elements whose name ends with one of `suffixes`.
  public func suffixed(_ suffixes: [String]) -> Selection {
    narrowed(
      to: elements.filter { element in
        suffixes.contains { element.name.hasSuffix($0) }
      },
      appending: "suffixed \(suffixes.quotedList)"
    )
  }

  /// Returns the elements whose name begins with one of `prefixes`.
  public func prefixed(_ prefixes: String...) -> Selection {
    prefixed(prefixes)
  }

  /// Returns the elements whose name begins with one of `prefixes`.
  public func prefixed(_ prefixes: [String]) -> Selection {
    narrowed(
      to: elements.filter { element in
        prefixes.contains { element.name.hasPrefix($0) }
      },
      appending: "prefixed \(prefixes.quotedList)"
    )
  }

  /// Returns the elements whose name matches the regular expression
  /// `pattern`.
  ///
  /// - Throws: ``CodebaseError/invalidRegularExpression(pattern:)`` when
  ///   `pattern` is invalid.
  public func nameMatching(
    _ pattern: String
  ) throws(CodebaseError) -> Selection {
    nameMatching(try NamePattern(pattern))
  }

  package func nameMatching(_ namePattern: NamePattern) -> Selection {
    narrowed(
      to: elements.filter { namePattern.matches($0.name) },
      appending: "with a name matching /\(namePattern.pattern)/"
    )
  }

  /// Returns the elements except those named in `names`.
  public func excluding(_ names: String...) -> Selection {
    excluding(names)
  }

  /// Returns the elements except those named in `names`.
  public func excluding(_ names: [String]) -> Selection {
    narrowed(
      to: elements.filter { !names.contains($0.name) },
      appending: "excluding \(names.quotedList)"
    )
  }
}

extension [String] {
  package var quotedList: String {
    map { "'\($0)'" }.joined(separator: " or ")
  }
}

package struct NamePattern: Sendable {
  package let pattern: String
  private let regex: NSRegularExpression

  package init(_ pattern: String) throws(CodebaseError) {
    self.pattern = pattern
    let wholeStringPattern = "\\A(?:\(pattern))\\z"
    do {
      regex = try NSRegularExpression(pattern: wholeStringPattern)
    } catch {
      throw .invalidRegularExpression(pattern: pattern)
    }
  }

  package func matches(_ name: String) -> Bool {
    let range = NSRange(name.startIndex..., in: name)
    return regex.firstMatch(in: name, range: range) != nil
  }
}

extension Selection {
  private func scopeDirectories(
    _ directories: [String]
  ) -> [LexicalFilePath] {
    let root = LexicalFilePath(rootPath)
    return directories.compactMap { directory in
      guard let resolved = root.resolvingDescendant(directory) else {
        QueryWarnings.record(
          Rule.Warning(
            message: "'\(directory)' is outside the codebase root",
            location: DeclarationLocation.start(of: rootPath)
          )
        )
        return nil
      }
      return resolved
    }
  }
}

extension Selection where Element: Located {
  /// Returns the elements in files at or below one of `directories`,
  /// relative to the codebase root.
  public func under(_ directories: String...) -> Selection {
    under(directories)
  }

  /// Returns the elements in files at or below one of `directories`,
  /// relative to the codebase root.
  public func under(_ directories: [String]) -> Selection {
    let relativeDirectories = directories.map(LexicalFilePath.init)
    let resolvedDirectories = scopeDirectories(directories)
    return narrowed(
      to: elements.filter { element in
        let path = LexicalFilePath(element.location.filePath)
        return resolvedDirectories.contains { $0.contains(path) }
      },
      appending: "under \(relativeDirectories.map(\.string).quotedList)"
    )
  }
}

extension Selection where Element: Located {
  /// Returns the elements in files outside `directories`, relative to
  /// the codebase root.
  public func outside(_ directories: String...) -> Selection {
    outside(directories)
  }

  /// Returns the elements in files outside `directories`, relative to
  /// the codebase root.
  public func outside(_ directories: [String]) -> Selection {
    let relativeDirectories = directories.map(LexicalFilePath.init)
    let resolvedDirectories = scopeDirectories(directories)
    return narrowed(
      to: elements.filter { element in
        let path = LexicalFilePath(element.location.filePath)
        return !resolvedDirectories.contains { $0.contains(path) }
      },
      appending: "outside \(relativeDirectories.map(\.string).quotedList)"
    )
  }
}

extension Selection: CustomStringConvertible {
  public var description: String {
    let elements = count == 1 ? "1 element" : "\(count) elements"
    return "\(elements): \(queryDescription)"
  }
}

extension Selection where Element: Named {
  package func filtering(_ filters: [NameFilter]) -> Selection {
    guard !filters.isEmpty else { return self }
    if QueryInspection.isEnabled {
      return filters.reduce(self) { selection, filter in
        selection.narrowed(
          to: selection.elements.filter { filter.matches($0.name) },
          appending: filter.description
        )
      }
    }
    return Selection(
      elements: elements.filter { element in
        filters.allSatisfy { $0.matches(element.name) }
      },
      queryDescription: ([queryDescription] + filters.map(\.description))
        .joined(separator: " "),
      rootPath: rootPath
    )
  }
}
