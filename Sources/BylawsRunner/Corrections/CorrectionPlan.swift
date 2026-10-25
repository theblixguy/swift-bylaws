import BylawsCore
package import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
package import Foundation

package struct CorrectionPlan {
  package struct Change {
    package let path: String
    package let resolvedPath: String
    package let original: Data
    package let replacement: Data
  }

  package let changes: [Change]
  package let diagnostics: [Diagnostic]
  package let fixCount: Int

  private struct Proposal {
    let ruleID: Rule.ID
    let location: DeclarationLocation
    let edits: [Edit]
    let layoutCandidates: [SourceFix.Edit]
  }

  private struct Edit: Hashable {
    let path: String
    let range: Range<Int>
    let replacement: Data
    let swiftLanguageMode: SwiftLanguageMode
    let sourceEdit: SourceFix.Edit

    init(_ edit: SourceFix.Edit, resolvedPath: String) {
      path = resolvedPath
      range = edit.source.range
      replacement = Data(edit.replacement.utf8)
      swiftLanguageMode = edit.source.snapshot.swiftLanguageMode
      sourceEdit = edit
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.path == rhs.path && lhs.range == rhs.range
        && lhs.replacement == rhs.replacement
        && lhs.swiftLanguageMode == rhs.swiftLanguageMode
        && lhs.sourceEdit.layout == rhs.sourceEdit.layout
        &&
        (lhs.sourceEdit.layout == nil || lhs.sourceEdit.source.snapshot == rhs
          .sourceEdit.source.snapshot)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(path)
      hasher.combine(range)
      hasher.combine(replacement)
      hasher.combine(swiftLanguageMode)
      hasher.combine(sourceEdit.layout)
      if sourceEdit.layout != nil { hasher.combine(sourceEdit.source.snapshot) }
    }
  }

  private struct Target {
    let path: String
    let resolvedPath: String
    let original: Data
  }

  package static func prepare(
    reports: [RuleReport],
    rootPath: String,
    reportPaths: [String] = [],
    protectedPaths: Set<String> = []
  ) -> Self {
    let root = LexicalFilePath(rootPath)
    let scope = reportPaths.isEmpty
      ? nil : ReportPathScope(paths: reportPaths, rootPath: rootPath)
    var proposals: [Proposal] = []
    var diagnostics: [Diagnostic] = []
    var targetsBySourcePath: [String: Result<Target, any Error>] = [:]
    var targetsByResolvedPath: [String: Target] = [:]
    var layoutCandidates: [SourceFix.Edit] = []
    for report in reports {
      layoutCandidates += report.violations.layoutCandidates
      for (offender, fix) in zip(
        report.violations.offenders,
        report.violations.fixes
      ) {
        guard let fix else { continue }
        let proposed = SourceFix(
          fix.title, proposedEdits: fix.edits,
          layoutCandidates: fix.layoutCandidates
        )
        let edits = proposed.edits
        let fixCandidates = proposed.layoutCandidates
        guard !edits.isEmpty else { continue }
        do {
          var proposedEdits: [Edit] = []
          for edit in edits {
            let path = edit.source.filePath
            if targetsBySourcePath[path] == nil {
              targetsBySourcePath[path] = Result {
                try validateTarget(
                  path, root: root, scope: scope,
                  protectedPaths: protectedPaths
                )
              }
            }
            guard let target = try targetsBySourcePath[path]?.get(),
                  target.original.elementsEqual(edit.source.snapshot.text.utf8)
            else {
              throw CaptureError(
                "the source changed at '\(path)'. Run the command again"
              )
            }
            if targetsByResolvedPath[target.resolvedPath] == nil {
              targetsByResolvedPath[target.resolvedPath] = target
            }
            proposedEdits.append(Edit(edit, resolvedPath: target.resolvedPath))
          }
          proposals.append(Proposal(
            ruleID: report.id, location: offender.location,
            edits: Array(Set(proposedEdits)), layoutCandidates: fixCandidates
          ))
        } catch {
          diagnostics.append(diagnostic(
            for: report.id, at: offender.location,
            message: String(describing: error)
          ))
        }
      }
    }
    let conflicts = conflictingProposals(proposals)
    var rejected = Set(conflicts.keys)
    for (index, reason) in conflicts.sorted(by: { $0.key < $1.key }) {
      let proposal = proposals[index]
      diagnostics.append(diagnostic(
        for: proposal.ruleID, at: proposal.location, message: reason
      ))
    }

    var changes: [Change] = []
    while true {
      let active = proposals.indices.filter { !rejected.contains($0) }
      let activeCandidates = layoutCandidates + active
        .flatMap { proposals[$0].layoutCandidates }
      let editsByPath = Dictionary(
        grouping: Set(active.flatMap { proposals[$0].edits }),
        by: \.path
      )
      changes = []
      var failedPaths: Set<String> = []
      for path in editsByPath.keys.sorted() {
        guard let edits = editsByPath[path],
              let first = edits.first else { continue }
        do {
          guard let target = targetsByResolvedPath[path] else { continue }
          changes.append(try prepareChange(
            at: path, target: target, edits: edits,
            swiftLanguageMode: first.swiftLanguageMode,
            layoutCandidates: activeCandidates
          ))
        } catch {
          failedPaths.insert(path)
          for index in active
            where proposals[index].edits
            .contains(where: { $0.path == path })
          {
            if rejected.insert(index).inserted {
              diagnostics.append(diagnostic(
                for: proposals[index].ruleID, at: proposals[index].location,
                message: "cannot prepare the correction for '\(path)': \(error)"
              ))
            }
          }
        }
      }
      if failedPaths.isEmpty { break }
    }
    return Self(
      changes: changes,
      diagnostics: diagnostics,
      fixCount: proposals.count - rejected.count
    )
  }

  private static func prepareChange(
    at path: String, target: Target, edits: [Edit],
    swiftLanguageMode: SwiftLanguageMode,
    layoutCandidates: [SourceFix.Edit]
  ) throws -> Change {
    var replacement = target.original
    let sourcePaths = Set(edits.map(\.sourceEdit.source.filePath))
    let candidates = layoutCandidates.filter {
      sourcePaths.contains($0.source.filePath)
        || LexicalFilePath($0.source.filePath).resolvingSymbolicLinks()?
        .string == path
    }
    if let source = edits.first?.sourceEdit.source,
       edits.allSatisfy({ $0.sourceEdit.source.snapshot == source.snapshot })
    {
      for candidate in candidates {
        guard candidate.source.snapshot == source.snapshot else {
          throw SourceError.differentSnapshots
        }
      }
      replacement = Data(try source.file.replacement(
        applying: edits.map(\.sourceEdit), layoutCandidates: candidates
      ).replacement.utf8)
    } else {
      guard candidates.isEmpty,
            edits.allSatisfy({ $0.sourceEdit.layout == nil })
      else {
        throw SourceError.differentSnapshots
      }
      for edit in edits
        .sorted(by: { $0.range.lowerBound > $1.range.lowerBound })
      {
        replacement.replaceSubrange(edit.range, with: edit.replacement)
      }
    }
    let text = String(decoding: replacement, as: UTF8.self)
    guard text.utf8.elementsEqual(replacement) else {
      throw CaptureError("the corrected source must contain UTF-8 text")
    }
    _ = try FileCollector.collect(
      source: text, path: path, swiftLanguageMode: swiftLanguageMode
    )
    return Change(
      path: target.path, resolvedPath: target.resolvedPath,
      original: target.original, replacement: replacement
    )
  }

  private static func validateTarget(
    _ path: String,
    root: LexicalFilePath,
    scope: ReportPathScope?,
    protectedPaths: Set<String>
  ) throws -> Target {
    let candidate = LexicalFilePath(path)
    // Foundation can shorten macOS paths that SwiftPM reports in physical form.
    guard let resolvedRoot = root.resolvingSymbolicLinks(),
          candidate.string == path,
          let relative = candidate.relative(to: root)
          ?? candidate.relative(to: resolvedRoot),
          let physicalPath = candidate.resolvingSymbolicLinks(),
          physicalPath == resolvedRoot.appending(relative.string),
          path.hasSuffix(".swift")
    else {
      throw CaptureError(
        "the correction must target a regular Swift file under '\(root.string)'"
      )
    }
    guard !protectedPaths.contains(where: {
      LexicalFilePath($0).resolvingSymbolicLinks() == physicalPath
    }) else {
      throw CaptureError(
        "the correction targets active rule or configuration source at '\(path)'"
      )
    }
    guard scope?.contains(path: path) != false else {
      throw CaptureError(
        "the correction targets '\(path)' outside --report-path"
      )
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
          (attributes[.referenceCount] as? NSNumber)?.intValue == 1,
          FileManager.default.isWritableFile(atPath: path)
    else {
      throw CaptureError(
        "the correction target must be a writable regular file at '\(path)'"
      )
    }
    return Target(
      path: root.appending(relative.string).string,
      resolvedPath: physicalPath.string,
      original: try Data(contentsOf: URL(fileURLWithPath: path))
    )
  }

  private static func conflictingProposals(_ proposals: [Proposal])
    -> [Int: String]
  {
    var ownersByPath: [String: [Edit: Set<Int>]] = [:]
    for (index, proposal) in proposals.enumerated() {
      for edit in proposal.edits {
        ownersByPath[edit.path, default: [:]][edit, default: []].insert(index)
      }
    }
    var rejected: [Int: String] = [:]
    for path in ownersByPath.keys.sorted() {
      guard let owners = ownersByPath[path] else { continue }
      var sessions: [SourceSnapshot: SourceLayoutComposition.Session] = [:]
      func canContain(_ parent: SourceFix.Edit, _ child: SourceFix.Edit)
        -> Bool
      {
        guard parent.layout != nil,
              parent.source.snapshot == child.source.snapshot
        else { return false }
        let snapshot = parent.source.snapshot
        let session: SourceLayoutComposition.Session
        if let existing = sessions[snapshot] {
          session = existing
        } else {
          session = SourceLayoutComposition.Session(snapshot: snapshot)
          sessions[snapshot] = session
        }
        return session.canContain(parent, child)
      }
      let edits = owners.keys.sorted {
        if $0.range.lowerBound == $1.range.lowerBound {
          return $0.range.upperBound < $1.range.upperBound
        }
        return $0.range.lowerBound < $1.range.lowerBound
      }
      let modes = Set(edits.map(\.swiftLanguageMode))
      if modes.count > 1 {
        let names = modes.map(\.rawValue).sorted().joined(separator: ", ")
        let reason = "the corrections for '\(path)' use different Swift language modes: \(names). Use the same swiftLanguageMode for this file in every rule."
        for index in owners.values.flatMap(\.self) {
          rejected[index] = reason
        }
        continue
      }
      for first in edits.indices {
        let lhs = edits[first].range
        for second in edits.indices.dropFirst(first + 1) {
          let rhs = edits[second].range
          if rhs.lowerBound > lhs.upperBound { break }
          let touchesInsertion = (lhs.isEmpty || rhs.isEmpty)
            && rhs.lowerBound <= lhs.upperBound
          if lhs.overlaps(rhs) || touchesInsertion {
            if canContain(
              edits[first].sourceEdit,
              edits[second].sourceEdit
            )
              || canContain(
                edits[second].sourceEdit,
                edits[first].sourceEdit
              )
            {
              continue
            }
            let affected = (owners[edits[first]] ?? [])
              .union(owners[edits[second]] ?? [])
            for index in affected {
              rejected[index] = rejected[index]
                ?? "the correction overlaps another replacement. Review the conflicting rules"
            }
          }
        }
      }
    }
    return rejected
  }

  private static func diagnostic(
    for ruleID: Rule.ID, at location: DeclarationLocation,
    message: String
  ) -> Diagnostic {
    Diagnostic(
      severity: .error,
      location: location,
      message: "rule '\(ruleID)': \(message)"
    )
  }
}
