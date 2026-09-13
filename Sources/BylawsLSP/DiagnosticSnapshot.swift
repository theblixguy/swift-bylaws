import BylawsCore
import BylawsRunner
import BylawsSemantics
import Foundation
import LanguageServerProtocol

struct DiagnosticSnapshot {
  let diagnosticsByURI: [DocumentURI: [LanguageServerProtocol.Diagnostic]]
  let resultID: String

  init(
    document: ReportDocument,
    overlay: SourceOverlay = .empty,
    generation: UInt
  ) {
    diagnosticsByURI = Dictionary(grouping: document.events) { event in
      DocumentURI(
        URL(fileURLWithPath: event.location.filePath).standardizedFileURL
      )
    }.mapValues { events in
      let fileData = events.first.flatMap {
        Self.sourceData(atPath: $0.location.filePath, from: overlay)
      }
      let lines = fileData.map { SourceLineTable($0) }
      return events
        .map { Self.diagnostic($0, fileData: fileData, lines: lines) }
    }
    resultID = String(generation)
  }

  init(
    diagnosticsByURI: [DocumentURI: [LanguageServerProtocol.Diagnostic]],
    resultID: String
  ) {
    self.diagnosticsByURI = diagnosticsByURI
    self.resultID = resultID
  }

  private static func sourceData(
    atPath path: String,
    from overlay: SourceOverlay
  ) -> Data? {
    if let overlaid = overlay.text(forFileAt: path) {
      return Data(overlaid.utf8)
    }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }

  private static func diagnostic(
    _ event: ReportDocument.Event,
    fileData: Data?,
    lines: SourceLineTable?
  ) -> LanguageServerProtocol.Diagnostic {
    let position = position(of: event, in: fileData, lines: lines)
    return LanguageServerProtocol.Diagnostic(
      range: position..<position,
      severity: severity(event.level),
      code: event.ruleID.map(DiagnosticCode.string),
      source: "Bylaws",
      message: event.messageWithoutRuleID
    )
  }

  private static func position(
    of event: ReportDocument.Event,
    in fileData: Data?,
    lines: SourceLineTable?
  ) -> Position {
    guard let fileData, let lines else {
      return Position(
        line: max(0, event.location.line - 1),
        utf16index: max(0, event.location.column - 1)
      )
    }
    let location = event.location
    let offset = min(max(
      0,
      location.utf8Offset
        ?? lines.offset(line: location.line, column: location.column)
        ?? lines.range(ofLine: location.line)?.lowerBound
        ?? fileData.count
    ), fileData.count)
    let resolved = lines.location(at: offset)
    let lineStart = offset - resolved.column + 1
    let linePrefix = String(
      decoding: fileData[lineStart..<offset],
      as: UTF8.self
    )
    return Position(
      line: resolved.line - 1,
      utf16index: linePrefix.utf16.count
    )
  }

  private static func severity(
    _ level: ReportDocument.Level
  ) -> DiagnosticSeverity {
    switch level {
    case .error: .error
    case .warning: .warning
    case .notice: .information
    }
  }
}
