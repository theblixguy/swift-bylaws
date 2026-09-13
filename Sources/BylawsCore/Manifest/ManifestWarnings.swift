package import BylawsSemantics

extension PackageManifest.UnresolvedValue {
  package var unreadableFieldMessage: String {
    let position = if let line, let column {
      " at line \(line), column \(column)"
    } else if let line {
      " at line \(line)"
    } else {
      ""
    }
    return """
    Bylaws cannot read all of `\(field)`\(position) in Package.swift. \
    This check may have missed dependencies.
    """
  }
}

extension [PackageManifest.UnresolvedValue] {
  // A manifest repeats the same unreadable field across targets.
  package func unreadableFieldWarnings(
    reportedAt location: DeclarationLocation
  ) -> [Rule.Warning] {
    var seen: Set<String> = []
    return compactMap { value in
      let message = value.unreadableFieldMessage
      guard seen.insert(message).inserted else { return nil }
      return Rule.Warning(message: message, location: location)
    }
  }
}

extension Rule.Warning {
  package static func emptyTargets(
    _ targets: [String],
    reportedAt location: DeclarationLocation
  ) -> [Rule.Warning] {
    targets.map { target in
      Rule.Warning(
        message: "target '\(target)' has no files in this codebase",
        location: location
      )
    }
  }
}
