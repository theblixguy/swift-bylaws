import BylawsSemantics
import Foundation

package struct PackageModuleIndex: Codable, Sendable {
  package struct Module: Codable, Sendable {
    package let name: String
    package let sourceFiles: [String]
    package let dependencies: [String]

    package init(
      name: String,
      sourceFiles: [String],
      dependencies: [String]
    ) {
      self.name = name
      self.sourceFiles = sourceFiles
      self.dependencies = dependencies
    }
  }

  package let modules: [Module]

  package init(modules: [Module]) throws(PackageModuleIndexError) {
    if let module = modules.first(where: { $0.name.isEmpty }) {
      throw PackageModuleIndexError.emptyModuleName(
        sourceFile: module.sourceFiles.first
      )
    }
    var names: Set<String> = []
    for module in modules where !names.insert(module.name).inserted {
      throw PackageModuleIndexError.duplicateModuleName(module.name)
    }
    for module in modules {
      guard !module.sourceFiles.isEmpty else {
        throw PackageModuleIndexError.missingSourceFiles(module: module.name)
      }
      if let path = module.sourceFiles.first(where: {
        $0.isEmpty || !$0.hasSuffix(".swift")
      }) {
        throw PackageModuleIndexError.invalidSourceFile(
          module: module.name,
          path: path
        )
      }
    }
    self.modules = modules
  }

  package init(contentsOf path: String) throws(PackageModuleIndexError) {
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw PackageModuleIndexError.unreadableFile(
        path: path,
        reason: error.reportableDescription
      )
    }
    let decoded: PackageModuleIndex
    do {
      decoded = try JSONDecoder().decode(PackageModuleIndex.self, from: data)
    } catch {
      throw PackageModuleIndexError.malformedFile(
        path: path,
        reason: error.reportableDescription
      )
    }
    try self.init(modules: decoded.modules)
  }
}

package enum PackageModuleIndexError: Error, Sendable, Hashable {
  case duplicateModuleName(String)
  case emptyModuleName(sourceFile: String?)
  case invalidSourceFile(module: String, path: String)
  case malformedFile(path: String, reason: String)
  case missingSourceFiles(module: String)
  case unreadableFile(path: String, reason: String)
}

extension PackageModuleIndexError: CustomStringConvertible, LocalizedError {
  package var description: String {
    switch self {
    case let .duplicateModuleName(name):
      "module name '\(name)' appears more than once"
    case let .emptyModuleName(sourceFile?):
      "the module containing '\(sourceFile)' has an empty name"
    case .emptyModuleName(nil):
      "a module has an empty name"
    case let .invalidSourceFile(module, path):
      "module '\(module)' has an empty or non-Swift source path: '\(path)'"
    case let .malformedFile(path, reason):
      "cannot decode the module index '\(path)': \(reason)"
    case let .missingSourceFiles(module):
      "module '\(module)' has no source files"
    case let .unreadableFile(path, reason):
      "cannot read the module index '\(path)': \(reason)"
    }
  }

  package var errorDescription: String? { description }
}
