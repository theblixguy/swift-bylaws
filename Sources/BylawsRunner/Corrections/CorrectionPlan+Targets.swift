import BylawsCore
import BylawsPaths
import Foundation

extension CorrectionPlan {
  struct Target {
    let path: String
    let resolvedPath: String
    let original: Data
  }

  struct TargetValidation {
    private let root: LexicalFilePath
    private let scope: ReportPathScope?
    private let protectedPaths: Set<String>
    private var resolvedProtectedPaths: Set<LexicalFilePath>?

    init(
      root: LexicalFilePath, scope: ReportPathScope?,
      protectedPaths: Set<String>
    ) {
      self.root = root
      self.scope = scope
      self.protectedPaths = protectedPaths
    }

    mutating func target(at path: String) throws -> Target {
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
      if resolvedProtectedPaths == nil {
        resolvedProtectedPaths = Set(protectedPaths.compactMap {
          LexicalFilePath($0).resolvingSymbolicLinks()
        })
      }
      guard resolvedProtectedPaths?.contains(physicalPath) != true else {
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
  }
}
