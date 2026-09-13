import Foundation

extension Error {
  // localizedDescription renders an error without LocalizedError as
  // Foundation's placeholder text.
  package var reportableDescription: String {
    switch self {
    case is CocoaError, is POSIXError, is URLError: localizedDescription
    default: String(describing: self)
    }
  }
}
