import BylawsCore
import Foundation

package enum ReportOutput {
  package static func validate(
    _ path: String, inputPaths: Set<String> = []
  ) throws {
    let destination = URL(fileURLWithPath: path).standardizedFileURL
    let resolved = destination.resolvingSymlinksInPath()
    guard destination.pathExtension.lowercased() != "swift",
          resolved.pathExtension.lowercased() != "swift",
          !inputPaths.contains(where: {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath() == resolved
          })
    else {
      throw CaptureError(
        "the report output overlaps source or configuration at '\(path)'; choose another output path"
      )
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      let attributes = try FileManager.default.attributesOfItem(
        atPath: destination.path
      )
      guard attributes[.type] as? FileAttributeType == .typeRegular,
            (attributes[.referenceCount] as? NSNumber)?.intValue == 1
      else {
        throw CaptureError(
          "the report output must be a regular file without links at '\(path)'; choose another output path"
        )
      }
    }
  }
}
