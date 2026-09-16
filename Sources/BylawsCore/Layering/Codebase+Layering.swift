public import BylawsSemantics

/// The result of checking a layering over a codebase.
public struct LayeringCheck: RuleResult, Hashable {
  /// A declared `mustImport` edge that no file uses.
  public struct MissingImport: Sendable, Hashable {
    /// The layer that must import ``requiredImport``.
    public let layer: String

    /// The layer that no file of ``layer`` imports.
    public let requiredImport: String

    /// Creates a missing-import record from a check's results.
    public init(layer: String, requiredImport: String) {
      self.layer = layer
      self.requiredImport = requiredImport
    }
  }

  /// Every import outside the layering's allowed edges.
  public let violations: Violations<Import>

  /// The names of the layers whose globs match no file.
  public let emptyLayers: [String]

  /// The `mustImport` edges that no file uses.
  public let missingImports: [MissingImport]
}

extension Codebase {
  /// Checks `layering` against every file in the codebase and returns
  /// the result.
  ///
  /// A file belongs to the layer whose globs match its path. Each import is
  /// compared with that layer's allowed imports. Modules absent from the
  /// layering are permitted. Empty layers are included in the result.
  ///
  /// - Throws: ``LayeringCheckError/invalidLayering(_:)`` for an invalid
  ///   layering declaration. A declaration is invalid when layer names are
  ///   not unique, when a `mayImport`, `mustImport` or `mustNotImport` name
  ///   matches no layer, when two layers declare the same module, when one
  ///   file matches two layers' globs, when a layer may import another layer
  ///   and must not import it, or when the declared edges form a cycle.
  ///   Throws ``LayeringCheckError/unreadableCodebase(_:)`` when the root
  ///   cannot be resolved, the root is not a directory, or a source path
  ///   cannot be read or parsed.
  public func checkLayering(
    _ layering: Layering
  ) async throws(LayeringCheckError) -> LayeringCheck {
    let parsedCodebase: ParsedCodebase
    do {
      parsedCodebase = try await CodebaseCache.shared.parsedCodebase(for: self)
    } catch {
      throw .unreadableCodebase(error)
    }
    do {
      return try LayeringCheck(layering, over: parsedCodebase)
    } catch {
      throw .invalidLayering(error)
    }
  }
}

extension LayeringCheck {
  fileprivate init(
    _ layering: Layering,
    over parsedCodebase: ParsedCodebase
  ) throws(LayeringError) {
    let plan = try LayeringPlan(layering, validatesModuleOwnership: true)
    var offenders: [Import] = []
    var checkedCount = 0
    var layersWithFiles: Set<String> = []
    var usedEdges: Set<LayeringPlan.Edge> = []

    for file in parsedCodebase.filesAsWritten {
      guard let layer = try plan.layer(
        containing: file.path,
        relativeTo: parsedCodebase.rootPath
      ) else { continue }
      layersWithFiles.insert(layer.name)

      for anImport in file.imports {
        checkedCount += 1
        guard let imported = plan.layerForModule[anImport.moduleName] else {
          continue
        }
        if imported != layer.name {
          usedEdges.insert(.init(source: layer.name, target: imported))
        }
        if !plan.allowsDependency(from: layer, to: imported) {
          offenders.append(anImport)
        }
      }
    }

    violations = Violations(
      rule: "follow the declared layering",
      offenders: offenders,
      checkedCount: checkedCount
    )
    emptyLayers = plan.emptyLayers(given: layersWithFiles)
    missingImports = plan.missingImports(given: usedEdges)
  }

  /// Returns rule findings for the layering result.
  ///
  /// Import violations keep their source locations. Unused `mustImport` edges
  /// and empty-layer warnings use `location`.
  ///
  /// - Parameter location: The position for empty-layer warnings and
  ///   missing required edges.
  public func findings(
    reportedAt location: DeclarationLocation
  ) -> Rule.Findings {
    Rule.Findings(
      layering: violations,
      missingImports: missingImports.map { edge in
        Offender(
          description: "layer '\(edge.layer)' does not import "
            + "'\(edge.requiredImport)'",
          name: "\(edge.layer) imports \(edge.requiredImport)",
          location: location
        )
      },
      emptyLayers: emptyLayers,
      reportedAt: location
    )
  }
}
