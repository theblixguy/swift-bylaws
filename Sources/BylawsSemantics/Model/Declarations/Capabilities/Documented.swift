import Foundation

/// A declaration that can carry a documentation comment.
public protocol Documented: Sendable {
  /// The documentation comment above the declaration, as written,
  /// or `nil` when there is none.
  var documentation: String? { get }
}

extension Documented {
  /// Whether the declaration has a documentation comment.
  public var isDocumented: Bool {
    documentation != nil
  }

  /// The parameter names the documentation comment describes, from
  /// `- Parameter x:` lines and `- Parameters:` blocks.
  public var documentedParameterNames: [String] {
    guard let documentation else { return [] }
    let callouts: Set = [
      "Parameter", "Parameters", "Returns", "Throws", "Note", "Warning",
      "Important", "Precondition", "Postcondition", "Complexity", "SeeAlso",
    ]
    var names: [String] = []
    var inParametersBlock = false
    for rawLine in documentation.split(separator: "\n") {
      let line = String(rawLine).withoutCommentMarkers
      if let name = line.itemText(after: "- Parameter ") {
        names.append(name)
        inParametersBlock = false
      } else if line == "- Parameters:" {
        inParametersBlock = true
      } else if inParametersBlock, let name = line.itemText(after: "- ") {
        if callouts.contains(name) {
          inParametersBlock = false
        } else {
          names.append(name)
        }
      } else if line.hasPrefix("- ") {
        inParametersBlock = false
      }
    }
    return names
  }

  /// Whether the documentation comment describes the return value with
  /// a `- Returns:` line.
  public var documentsReturnValue: Bool {
    documentation?.split(separator: "\n").contains { line in
      String(line).withoutCommentMarkers.hasPrefix("- Returns:")
    } ?? false
  }
}

extension String {
  fileprivate var withoutCommentMarkers: String {
    var line = Substring(trimmingCharacters(in: .whitespaces))
    for marker in ["///", "/**", "*/", "*"] where line.hasPrefix(marker) {
      line = line.dropFirst(marker.count)
      break
    }
    return line.trimmingCharacters(in: .whitespaces)
  }

  fileprivate func itemText(after prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    let start = index(startIndex, offsetBy: prefix.count)
    guard let colon = self[start...].firstIndex(of: ":") else { return nil }
    let name = String(self[start..<colon])
      .trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
  }
}
