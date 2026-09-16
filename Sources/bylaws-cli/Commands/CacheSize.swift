import ArgumentParser

struct CacheSize: ExpressibleByArgument {
  let bytes: Int

  init?(argument: String) {
    let digits = argument.prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty, let value = Int(digits) else { return nil }
    let multiplier: Int
    switch argument.dropFirst(digits.count).lowercased() {
    case "", "b": multiplier = 1
    case "kb": multiplier = 1000
    case "mb": multiplier = 1_000_000
    case "gb": multiplier = 1_000_000_000
    case "kib": multiplier = 1024
    case "mib": multiplier = 1024 * 1024
    case "gib": multiplier = 1024 * 1024 * 1024
    default: return nil
    }
    let result = value.multipliedReportingOverflow(by: multiplier)
    guard !result.overflow else { return nil }
    bytes = result.partialValue
  }
}
