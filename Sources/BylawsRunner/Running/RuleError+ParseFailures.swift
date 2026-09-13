import BylawsCore
import BylawsIndex
import BylawsInterpreter

extension RuleError {
  var pathsThatDidNotParse: [String] {
    switch cause {
    case .cancelled: []
    case let .codebase(error): Self.pathsThatDidNotParse(in: error)
    case let .layering(error): Self.pathsThatDidNotParse(in: error)
    case let .other(error): Self.pathsThatDidNotParse(in: error)
    }
  }

  private static func pathsThatDidNotParse(in error: any Error) -> [String] {
    switch error {
    case let CodebaseError.didNotParse(paths):
      paths
    case let LayeringCheckError.unreadableCodebase(error),
         let IndexedLayeringError.unreadableCodebase(error),
         let ProjectIndexError.unreadableCodebase(error),
         let RuntimeIndexError.unreadableCodebase(error):
      pathsThatDidNotParse(in: error)
    case let error as RuntimeError:
      error.pathsThatDidNotParse ?? []
    default:
      []
    }
  }
}
