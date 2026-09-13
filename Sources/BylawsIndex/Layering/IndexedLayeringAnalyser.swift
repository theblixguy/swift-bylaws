package import BylawsCore
package import BylawsIndexStore
import BylawsPaths
package import BylawsSemantics

package struct IndexedLayeringAnalyser {
  package struct Findings: Sendable {
    package let violations: Violations<Offender>
    package let emptyLayers: [String]
    package let missingImports: [LayeringCheck.MissingImport]
  }

  private let plan: LayeringPlan
  private let layerByFile: [String: Layer]

  package init(
    layering: Layering,
    parsedCodebase: ParsedCodebase
  ) throws(LayeringError) {
    plan = try LayeringPlan(
      layering,
      validatesModuleOwnership: false
    )
    var layerByFile: [String: Layer] = [:]
    for file in parsedCodebase.files {
      if let layer = try plan.layer(
        containing: file.path,
        relativeTo: parsedCodebase.rootPath
      ) {
        layerByFile[Self.standardisedPath(file.path)] = layer
      }
    }
    self.layerByFile = layerByFile
  }

  package func check(
    occurrenceGroups: [[IndexReference]]
  ) -> Findings {
    var checkedDependencies: Set<Dependency> = []
    var offenders: [Offender] = []
    var usedEdges: Set<LayeringPlan.Edge> = []

    for occurrences in occurrenceGroups {
      let definitions = preferredDefinitions(in: occurrences)
      let targetsByModule = Dictionary(grouping: definitions, by: \.module)
        .mapValues { definitions in
          Set(definitions.compactMap { definition in
            layerByFile[Self.standardisedPath(definition.file)]?.name
          })
        }
      for reference in occurrences where isExplicitReference(reference) {
        guard let source = layerByFile[Self.standardisedPath(reference.file)]
        else {
          continue
        }
        guard let targets = targetsByModule[reference.module],
              targets.count == 1, let target = targets.first else { continue }

        let dependency = Dependency(reference: reference, target: target)
        guard checkedDependencies.insert(dependency).inserted else { continue }
        guard source.name != target else { continue }
        usedEdges.insert(.init(source: source.name, target: target))
        guard !plan.allowsDependency(from: source, to: target) else {
          continue
        }
        offenders.append(
          Offender(
            description: "\(reference.symbol.name) in layer "
              + "'\(source.name)' depends on layer '\(target)'",
            name: reference.symbol.name,
            location: reference.location
          )
        )
      }
    }

    return Findings(
      violations: Violations(
        rule: "follow the declared layering",
        offenders: offenders.sorted(by: Self.inSourceOrder),
        checkedCount: checkedDependencies.count
      ),
      emptyLayers: plan.emptyLayers(
        given: Set(layerByFile.values.map(\.name))
      ),
      missingImports: plan.missingImports(given: usedEdges)
    )
  }

  private func preferredDefinitions(
    in occurrences: [IndexReference]
  ) -> [IndexReference] {
    let definitions = occurrences.filter {
      $0.roles.contains(.definition)
        && !$0.roles.contains(.implicit)
        && layerByFile[Self.standardisedPath($0.file)] != nil
    }
    if !definitions.isEmpty { return definitions }
    return occurrences.filter {
      $0.roles.contains(.declaration)
        && !$0.roles.contains(.implicit)
        && layerByFile[Self.standardisedPath($0.file)] != nil
    }
  }

  private func isExplicitReference(_ reference: IndexReference) -> Bool {
    reference.roles.contains(.reference)
      && !reference.roles.contains(.definition)
      && !reference.roles.contains(.declaration)
      && !reference.roles.contains(.implicit)
  }

  private static func standardisedPath(_ path: String) -> String {
    LexicalFilePath(path).string
  }

  private static func inSourceOrder(_ lhs: Offender, _ rhs: Offender) -> Bool {
    let left = lhs.location
    let right = rhs.location
    if left.filePath != right.filePath { return left.filePath < right.filePath }
    if left.line != right.line { return left.line < right.line }
    if left.column != right.column { return left.column < right.column }
    return (lhs.name ?? "") < (rhs.name ?? "")
  }

  private struct Dependency: Hashable {
    let file: String
    let line: Int
    let column: Int
    let usr: String
    let target: String

    init(reference: IndexReference, target: String) {
      file = IndexedLayeringAnalyser.standardisedPath(reference.file)
      line = reference.line
      column = reference.column
      usr = reference.symbol.usr
      self.target = target
    }
  }
}

extension IndexedLayeringAnalyser.Findings {
  package func findings(
    reportedAt location: DeclarationLocation
  ) -> Rule.Findings {
    Rule.Findings(
      layering: violations,
      missingImports: missingImports.map { edge in
        Offender(
          description: "layer '\(edge.layer)' does not depend on "
            + "layer '\(edge.requiredImport)'",
          name: "\(edge.layer) depends on \(edge.requiredImport)",
          location: location
        )
      },
      emptyLayers: emptyLayers,
      reportedAt: location
    )
  }
}
