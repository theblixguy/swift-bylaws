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
  }

  private struct Edit: Hashable {
    let path: String
    let range: Range<Int>
    let replacement: Data
    let swiftLanguageMode: SwiftLanguageMode

    init(_ edit: SourceFix.Edit) {
      path = edit.source.filePath
      range = edit.source.range
      replacement = Data(edit.replacement.utf8)
      swiftLanguageMode = edit.source.snapshot.swiftLanguageMode
    }
  }

  private struct Target {
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
    var targets: [String: Result<Target, any Error>] = [:]
    for report in reports {
      for (offender, fix) in zip(
        report.violations.offenders,
        report.violations.fixes
      ) {
        guard let fix else { continue }
        let edits = fix.edits.filter {
          !$0.source.text.utf8.elementsEqual($0.replacement.utf8)
        }
        guard !edits.isEmpty else { continue }
        let proposal = Proposal(
          ruleID: report.id, location: offender.location,
          edits: Array(Set(edits.map(Edit.init)))
        )
        do {
          for edit in edits {
            let path = edit.source.filePath
            if targets[path] == nil {
              targets[path] = Result {
                try validateTarget(
                  path, root: root, scope: scope,
                  protectedPaths: protectedPaths
                )
              }
            }
            guard let target = try targets[path]?.get(),
                  target.original == Data(edit.source.snapshot.text.utf8)
            else {
              throw CaptureError(
                "the source changed at '\(path)'. Run the command again"
              )
            }
          }
          proposals.append(proposal)
        } catch {
          diagnostics.append(diagnostic(
            for: proposal,
            message: String(describing: error)
          ))
        }
      }
    }
    let conflicts = conflictingProposals(proposals)
    var rejected = Set(conflicts.keys)
    for (index, reason) in conflicts.sorted(by: { $0.key < $1.key }) {
      diagnostics.append(diagnostic(for: proposals[index], message: reason))
    }

    var changes: [Change] = []
    while true {
      let active = proposals.indices.filter { !rejected.contains($0) }
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
          guard let target = try targets[path]?.get() else { continue }
          changes.append(try prepareChange(
            at: path, target: target, edits: edits,
            swiftLanguageMode: first.swiftLanguageMode
          ))
        } catch {
          failedPaths.insert(path)
          for index in active
            where proposals[index].edits
            .contains(where: { $0.path == path })
          {
            if rejected.insert(index).inserted {
              diagnostics.append(diagnostic(
                for: proposals[index],
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
    swiftLanguageMode: SwiftLanguageMode
  ) throws -> Change {
    var replacement = target.original
    for edit in edits.sorted(by: {
      $0.range.lowerBound > $1.range.lowerBound
    }) {
      replacement.replaceSubrange(edit.range, with: edit.replacement)
    }
    let text = String(decoding: replacement, as: UTF8.self)
    guard text.utf8.elementsEqual(replacement) else {
      throw CaptureError("the corrected source must contain UTF-8 text")
    }
    _ = try FileCollector.collect(
      source: text, path: path, swiftLanguageMode: swiftLanguageMode
    )
    return Change(
      path: path, resolvedPath: target.resolvedPath,
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
    let resolvedRoot = URL(fileURLWithPath: root.string)
      .resolvingSymlinksInPath()
    guard candidate.string == path,
          let relative = candidate.relative(to: root),
          URL(fileURLWithPath: path).resolvingSymlinksInPath().path
          == resolvedRoot.appendingPathComponent(relative.string).path,
          path.hasSuffix(".swift")
    else {
      throw CaptureError(
        "the correction must target a regular Swift file under '\(root.string)'"
      )
    }
    let physicalPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    guard !protectedPaths.contains(where: {
      URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == physicalPath
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
      resolvedPath: physicalPath,
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
    for proposal: Proposal,
    message: String
  ) -> Diagnostic {
    Diagnostic(
      severity: .error,
      location: proposal.location,
      message: "rule '\(proposal.ruleID)': \(message)"
    )
  }
}
