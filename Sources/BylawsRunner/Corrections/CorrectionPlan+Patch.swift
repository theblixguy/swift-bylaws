import Foundation

extension CorrectionPlan {
  package var patch: String {
    changes.map { change in
      let old = String(decoding: change.original, as: UTF8.self)
      let new = String(decoding: change.replacement, as: UTF8.self)
      let oldLines = patchLines(old)
      let newLines = patchLines(new)
      let path = patchPath(change.path)
      return "--- \(path)\t\n+++ \(path)\t\n"
        + "@@ -\(oldLines.isEmpty ? 0 : 1),\(oldLines.count) "
        + "+\(newLines.isEmpty ? 0 : 1),\(newLines.count) @@\n"
        + patchBody(oldLines, prefix: "-", finalNewline: old.utf8.last == 0x0A)
        + patchBody(newLines, prefix: "+", finalNewline: new.utf8.last == 0x0A)
    }.joined()
  }

  private func patchPath(_ path: String) -> String {
    guard path.utf8.contains(where: {
      $0 < 0x20 || $0 >= 0x7F || $0 == 0x22 || $0 == 0x5C
    }) else { return path }
    let escaped = path.utf8.map { byte in
      switch byte {
      case 0x07: "\\a"
      case 0x08: "\\b"
      case 0x09: "\\t"
      case 0x0A: "\\n"
      case 0x0B: "\\v"
      case 0x0C: "\\f"
      case 0x0D: "\\r"
      case 0x22: "\\\""
      case 0x5C: "\\\\"
      case 0x20...0x7E: String(UnicodeScalar(byte))
      default: "\\\(byte >> 6)\((byte >> 3) & 7)\(byte & 7)"
      }
    }.joined()
    return "\"\(escaped)\""
  }

  private func patchLines(_ text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    var lines = text.utf8.split(
      separator: 0x0A, omittingEmptySubsequences: false
    ).map { String(decoding: $0, as: UTF8.self) }
    if text.utf8.last == 0x0A { lines.removeLast() }
    return lines
  }

  private func patchBody(
    _ lines: [String], prefix: String, finalNewline: Bool
  ) -> String {
    let newlineMarker = if !lines.isEmpty, !finalNewline {
      "\\ No newline at end of file\n"
    } else { "" }
    return lines.map { "\(prefix)\($0)\n" }.joined() + newlineMarker
  }
}
