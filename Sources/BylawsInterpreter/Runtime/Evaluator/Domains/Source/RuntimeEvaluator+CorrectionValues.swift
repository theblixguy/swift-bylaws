import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func correctionMember(
    _ name: SupportedAPI.Member, of value: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> RuntimeValue? {
    if name == .correction {
      return try .sourceCorrection(value.correction(at: location))
    }
    switch value {
    case .genericType("SourceCorrection", _):
      return switch name {
      case .notApplicable: .sourceCorrection(.notApplicable)
      case .satisfied: .sourceCorrection(.satisfied)
      case .outcomeType: .genericType(
          name: "SourceCorrection.Outcome",
          arguments: []
        )
      default: nil
      }
    case let .sourceCorrection(correction):
      return switch name {
      case .fix: .optional(correction.fix.map(RuntimeValue.sourceFix))
      case .reason: .optional(correction.reason.map(RuntimeValue.string))
      case .outcome: .member(.constant(correction.outcome.literal))
      default: nil
      }
    case let .sourceFix(fix):
      return switch name {
      case .edits: .array(fix.edits.map(RuntimeValue.sourceEdit))
      case .title: .optional(fix.title.map(RuntimeValue.string))
      default: nil
      }
    default: return nil
    }
  }

  func correctionMethod(
    _ name: SupportedAPI.Method, of value: RuntimeValue,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue? {
    switch value {
    case .genericType("SourceCorrection", _):
      let reason = try arguments.string(at: 0)
      return switch name {
      case .unavailable: .sourceCorrection(.unavailable(reason))
      case .undetermined: .sourceCorrection(.undetermined(reason))
      default: nil
      }
    case let .sourceCorrection(correction) where name == .preparedFix:
      do {
        return try .optional(correction.preparedFix()
          .map(RuntimeValue.sourceFix))
      } catch { throw RuntimeError(wrapping: error, at: arguments.location) }
    default: return nil
    }
  }

  func constructCorrection(_ arguments: RuntimeArguments) throws(RuntimeError)
    -> RuntimeValue
  {
    guard arguments.values.count == 1 else {
      throw RuntimeError(
        message: "SourceCorrection takes edits, a fix or combined corrections",
        location: arguments.location
      )
    }
    let value = try arguments.value(at: 0)
    if arguments.label(at: 0) == .edits {
      return try .sourceCorrection(SourceCorrection(edits: value
          .correctionEdits(at: arguments.location)))
    }
    return try .sourceCorrection(value.correction(at: arguments.location))
  }
}

extension SourceCorrection.Outcome {
  fileprivate var literal: SupportedAPI.MemberLiteral.Constant {
    switch self {
    case .notApplicable: .notApplicable
    case .satisfied: .satisfied
    case .violation: .violation
    case .undetermined: .undetermined
    }
  }
}
