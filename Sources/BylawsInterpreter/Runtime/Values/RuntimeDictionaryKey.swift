import BylawsSemantics
import Foundation

enum RuntimeDictionaryKey: Hashable, Sendable {
  case string(String)
  case integer(Int)
  case boolean(Bool)
  case url(URL)

  init(
    _ value: RuntimeValue,
    at location: DeclarationLocation
  ) throws(RuntimeError) {
    self = switch value {
    case let .string(value): .string(value)
    case let .integer(value): .integer(value)
    case let .boolean(value): .boolean(value)
    case let .url(value): .url(value)
    default:
      throw RuntimeError(
        message: "Dictionary keys must be String, Int, Bool or URL",
        location: location
      )
    }
  }

  var value: RuntimeValue {
    switch self {
    case let .string(value): .string(value)
    case let .integer(value): .integer(value)
    case let .boolean(value): .boolean(value)
    case let .url(value): .url(value)
    }
  }
}
