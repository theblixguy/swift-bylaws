import BylawsCore
import BylawsIndex
import BylawsInterpreter
import BylawsSemantics

extension RuleError {
  var pathsThatDidNotParse: [String] {
    Array(Set(parseDiagnostics.map(\.location.filePath))).sorted()
  }

  var parseDiagnostics: [SourceParseDiagnostic] {
    switch cause {
    case .cancelled: []
    case let .codebase(error): Self.parseDiagnostics(in: error)
    case let .layering(error): Self.parseDiagnostics(in: error)
    case let .other(error): Self.parseDiagnostics(in: error)
    }
  }

  private static func parseDiagnostics(in error: any Error)
    -> [SourceParseDiagnostic]
  {
    switch error {
    case let CodebaseError.didNotParse(diagnostics):
      diagnostics
    case let LayeringCheckError.unreadableCodebase(error),
         let IndexedLayeringError.unreadableCodebase(error),
         let ProjectIndexError.unreadableCodebase(error),
         let RuntimeIndexError.unreadableCodebase(error):
      parseDiagnostics(in: error)
    case let error as RuntimeError:
      error.parseDiagnostics ?? []
    default:
      []
    }
  }
}
