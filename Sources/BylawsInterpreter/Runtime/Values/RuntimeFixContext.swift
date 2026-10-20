import BylawsCore
import BylawsSemantics

struct RuntimeFixContext: Sendable {
  let offender: RuntimeModelValue
  let codebase: Codebase?

  func member(
    _ name: SupportedAPI.Member,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue {
    do {
      switch name {
      case .offender: return .model(offender)
      case .source: return .sourceSlice(try offender.source)
      case .file: return .sourceSlice(try offender.source.file)
      case .codebase:
        guard let codebase else {
          throw RuntimeError(
            message: "the fix has no codebase context. Use a Codebase query.",
            location: location
          )
        }
        return .codebase(codebase)
      default:
        throw RuntimeError(
          message: "'\(name.rawValue)' is not a supported FixContext member",
          location: location
        )
      }
    } catch {
      throw RuntimeError(wrapping: error, at: location)
    }
  }
}
