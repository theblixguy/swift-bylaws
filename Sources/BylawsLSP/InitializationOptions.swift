import BylawsCore
import BylawsPaths
import LanguageServerProtocol

struct InitializationOptions {
  fileprivate enum Key: String {
    case baseline
    case only
    case refreshDelayMilliseconds
    case rules
    case skip
    case strict
    case swiftPackageModules
  }

  var baseline: String?
  var only: [String] = []
  var refreshDelay = Duration.zero
  var ruleFilePaths: [LexicalFilePath] = []
  var skip: [String] = []
  var strict = false
  var swiftPackageModules: String?

  init(_ value: LSPAny?, root: LexicalFilePath) {
    guard case let .dictionary(values) = value else { return }
    baseline = values.string(for: .baseline).map {
      LexicalFilePath($0, relativeTo: root).string
    }
    only = values.strings(for: .only)
    if let milliseconds = values.integer(for: .refreshDelayMilliseconds) {
      refreshDelay = .milliseconds(max(0, milliseconds))
    }
    ruleFilePaths = values.strings(for: .rules).map {
      LexicalFilePath($0, relativeTo: root)
    }
    skip = values.strings(for: .skip)
    if case let .bool(strict) = values[Key.strict.rawValue] {
      self.strict = strict
    }
    swiftPackageModules = values.string(for: .swiftPackageModules).map {
      LexicalFilePath($0, relativeTo: root).string
    }
  }
}

extension [String: LSPAny] {
  fileprivate func integer(for key: InitializationOptions.Key) -> Int? {
    guard case let .int(value) = self[key.rawValue] else { return nil }
    return value
  }

  fileprivate func string(for key: InitializationOptions.Key) -> String? {
    guard case let .string(value) = self[key.rawValue] else { return nil }
    return value
  }

  fileprivate func strings(for key: InitializationOptions.Key) -> [String] {
    guard case let .array(values) = self[key.rawValue] else { return [] }
    return values.compactMap { value in
      guard case let .string(value) = value else { return nil }
      return value
    }
  }
}
