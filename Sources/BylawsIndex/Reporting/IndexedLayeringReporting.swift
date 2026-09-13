#if canImport(Testing)
  public import BylawsCore
  @_weakLinked public import Testing

  extension Codebase {
    /// Checks index-backed dependencies between file-based layers and returns
    /// the violations.
    ///
    /// The check records a non-failing issue for an empty layer, and a failure
    /// for a `mustImport` edge with no indexed dependency.
    ///
    /// - Parameters:
    ///   - layering: The file globs and allowed dependency edges to check.
    ///   - modules: The indexed modules to read, or `nil` for all modules.
    ///   - unitOutputFiles: The build units to read, or `nil` when the index
    ///     contains one build configuration.
    ///   - sourceLocation: Where to report failures and other issues.
    /// - Returns: The explicit index-backed dependencies outside the allowed
    ///   layering edges.
    /// - Throws: ``IndexedLayeringError/invalidLayering(_:)`` when the
    ///   layering declaration is invalid,
    ///   ``IndexedLayeringError/indexUnavailable(_:)`` when the index is
    ///   unavailable, and ``IndexedLayeringError/unreadableCodebase(_:)`` when
    ///   the codebase root or a source path cannot be read or parsed.
    public func indexedViolations(
      of layering: Layering,
      modules: Set<String>? = nil,
      unitOutputFiles: Set<String>? = nil,
      sourceLocation: SourceLocation = #_sourceLocation
    ) async throws(IndexedLayeringError) -> Violations<Offender> {
      let result = try await indexedLayeringCheck(
        layering,
        modules: modules,
        unitOutputFiles: unitOutputFiles
      )
      for name in result.emptyLayers {
        Issue.recordIndexWarning(
          Comment(rawValue: LayeringCheck.emptyLayerIssue(name)),
          sourceLocation: sourceLocation
        )
      }
      for missing in result.missingImports {
        Issue.record(
          """
          Layer '\(missing.layer)' must depend on \
          '\(missing.requiredImport)', but no indexed symbol reference in \
          '\(missing.layer)' establishes that dependency.
          """,
          sourceLocation: sourceLocation
        )
      }
      return result.violations
    }
  }

  // BylawsIndex does not import Bylaws, where Issue.recordWarning lives.
  extension Issue {
    fileprivate static func recordIndexWarning(
      _ comment: Comment,
      sourceLocation: SourceLocation
    ) {
      #if compiler(>=6.3)
        Issue.record(
          comment,
          severity: .warning,
          sourceLocation: sourceLocation
        )
      #else
        withKnownIssue(isIntermittent: true, sourceLocation: sourceLocation) {
          Issue.record(comment, sourceLocation: sourceLocation)
        }
      #endif
    }
  }
#endif
