package import BylawsCore
package import BylawsIndexStore
import BylawsPaths
package import BylawsSemantics

package struct DependencyAnalyser {
  private let plan: DependencyPlan

  package init(plan: DependencyPlan) {
    self.plan = plan
  }

  package func check(
    occurrenceGroups: some Sequence<[IndexReference]>,
    checkingCycles: Bool,
    reportedAt location: DeclarationLocation
  ) -> Rule.Findings {
    var offenders: Set<Offender> = []
    var checked: Set<IndexReference> = []
    var edgeLocations: [DirectedEdge<String>: DeclarationLocation] = [:]
    var ambiguousSymbols: Set<String> = []
    var indexedGroups: Set<String> = []
    var indexedFiles: Set<String> = []
    for occurrences in occurrenceGroups {
      let declarations = occurrences.filter {
        !$0.roles.contains(.implicit)
          && ($0.roles.contains(.definition) || $0.roles.contains(.declaration))
          && plan.files[LexicalFilePath($0.file).string] != nil
      }
      let definitions = declarations.filter { $0.roles.contains(.definition) }
      let targets = Set((definitions.isEmpty ? declarations : definitions)
        .compactMap { plan.files[LexicalFilePath($0.file).string] })
      for declaration in declarations {
        indexedFiles.insert(LexicalFilePath(declaration.file).string)
        if let group = plan.files[LexicalFilePath(declaration.file).string]?
          .group
        {
          indexedGroups.insert(group)
        }
      }
      for reference in occurrences where Self.isExplicitReference(reference) {
        guard let source = plan.files[LexicalFilePath(reference.file).string],
              source.isSource, !checkingCycles || source.group != nil
        else { continue }
        indexedFiles.insert(source.path)
        if let group = source.group { indexedGroups.insert(group) }
        guard !targets.isEmpty else { continue }
        guard targets.count == 1, let target = targets.first else {
          ambiguousSymbols.insert(reference.symbol.name)
          continue
        }
        guard !checkingCycles || target.group != nil else { continue }
        guard checked.insert(reference).inserted else { continue }
        if checkingCycles, let from = source.group, let to = target.group,
           from != to
        {
          let edge = DirectedEdge(from: from, to: to)
          edgeLocations[edge] = if let previous = edgeLocations[edge] {
            Self.precedes(reference.location, previous)
              ? reference.location : previous
          } else {
            reference.location
          }
        }
        guard !checkingCycles else { continue }
        let allowed = source.path == target.path || target.isAllowed
          || (source.group != nil && source.group == target.group)
        guard !allowed else { continue }
        offenders.insert(Offender(
          description: "\(reference.symbol.name) is defined in '\(target.path)', outside the permitted dependency paths",
          name: reference.symbol.name,
          location: reference.location
        ))
      }
    }
    let edges = edgeLocations.keys.sorted {
      ($0.source, $0.destination) < ($1.source, $1.destination)
    }
    if checkingCycles,
       let cycle = OrderedDirectedGraph(nodes: plan.groups, edges: edges)
       .firstCycle()
    {
      let description = "dependency cycle: " + cycle
        .joined(separator: " -> ")
      for (source, destination) in zip(cycle, cycle.dropFirst()) {
        guard let position =
          edgeLocations[.init(from: source, to: destination)]
        else { continue }
        offenders.insert(Offender(description: description, location: position))
      }
    }
    var warnings: [Rule.Warning] = []
    if checkingCycles, plan.groups.isEmpty {
      warnings.append(.init(
        message: "Dependency cycle check has no groups. Add groups or check the folder discovery pattern.",
        location: location
      ))
    }
    let missingIndexPaths = if checkingCycles {
      plan.groups.filter { !indexedGroups.contains($0) }
    } else {
      plan.files.values
        .filter { $0.isSource && !indexedFiles.contains($0.path) }
        .map(\.path).sorted()
    }
    warnings += missingIndexPaths.map {
      Rule.Warning(
        message: "'\($0)' has no indexed declarations or references. Check the selected files and build modules.",
        location: location
      )
    }
    if plan.groups.isEmpty, let pattern = plan.folderPattern {
      warnings.append(.init(
        message: "'\(pattern)' matches no folders in the selected source files. Check the pattern and codebase paths.",
        location: location
      ))
    }
    if !checkingCycles, !plan.files.values.contains(where: \.isSource) {
      warnings.append(.init(
        message: "Source selection matches no files. Check the source patterns and codebase paths.",
        location: location
      ))
    }
    for symbol in ambiguousSymbols.sorted() {
      warnings.append(.init(
        message: "cannot assign '\(symbol)' to one definition file. Select one build configuration and check its declarations.",
        location: location
      ))
    }
    return Rule.Findings(
      violations: Violations(
        rule: checkingCycles ? "avoid dependency cycles" :
          "reference only permitted files",
        offenders: offenders.sorted {
          if $0.location != $1.location {
            return Self.precedes($0.location, $1.location)
          }
          return $0.description < $1.description
        },
        checkedCount: checked.count
      ),
      warnings: warnings
    )
  }

  private static func isExplicitReference(_ reference: IndexReference) -> Bool {
    reference.roles.contains(.reference)
      && !reference.roles.contains(.definition)
      && !reference.roles.contains(.declaration)
      && !reference.roles.contains(.implicit)
  }

  private static func precedes(
    _ lhs: DeclarationLocation,
    _ rhs: DeclarationLocation
  ) -> Bool {
    (lhs.filePath, lhs.line, lhs.column) < (rhs.filePath, rhs.line, rhs.column)
  }
}
