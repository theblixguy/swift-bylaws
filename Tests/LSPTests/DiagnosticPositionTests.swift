import BylawsCore
import BylawsRunner
import BylawsSemantics
import Foundation
import LanguageServerProtocol
import Testing
@testable import BylawsInterpreter
@testable import BylawsLSP

@Suite("Diagnostic source positions")
struct DiagnosticPositionTests {
  @Test("Known zero offset points to the start of the file")
  func zeroOffset() throws {
    let location = DeclarationLocation(
      filePath: "/virtual/App.swift",
      line: 1,
      column: 1,
      utf8Offset: 0
    )
    let snapshot = DiagnosticSnapshot(
      document: ReportDocument(reports: [], diagnostics: [
        BylawsInterpreter.Diagnostic(
          severity: .error,
          location: location,
          message: "Cannot use Model"
        ),
      ]),
      overlay: SourceOverlay([location.filePath: "😀 Model"]),
      generation: 1
    )
    let diagnostic = try #require(snapshot.diagnosticsByURI.values.first?.first)
    #expect(diagnostic.range.lowerBound == Position(line: 0, utf16index: 0))
  }

  @Test("Index columns convert to UTF-16", arguments: ["\n", "\r\n", "\r"])
  func indexColumn(_ newline: String) throws {
    let reference = RuntimeIndexReference(
      symbol: RuntimeIndexSymbol(usr: "s:Model", name: "Model", kind: .struct),
      module: "App", file: "/virtual/App.swift", line: 2, column: 6,
      roles: [.reference]
    )
    let location = reference.offender.location
    let snapshot = DiagnosticSnapshot(
      document: ReportDocument(reports: [], diagnostics: [
        BylawsInterpreter.Diagnostic(
          severity: .error,
          location: location,
          message: "Cannot use Model"
        ),
      ]),
      overlay: SourceOverlay([location.filePath: "first\(newline)😀 Model"]),
      generation: 1
    )
    let diagnostic = try #require(snapshot.diagnosticsByURI.values.first?.first)
    #expect(diagnostic.range.lowerBound.line == 1)
    #expect(diagnostic.range.lowerBound.utf16index == 3)
  }
}
