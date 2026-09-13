import Foundation
import PackagePlugin

struct PackageModuleIndex: Encodable {
  let modules: [Module]

  init(package root: Package) throws {
    var packages: [Package] = []
    var seenPackages: Set<Package.ID> = []
    var pending = [root]
    while let package = pending.popLast() {
      guard seenPackages.insert(package.id).inserted else { continue }
      packages.append(package)
      pending.append(contentsOf: package.dependencies.map(\.package))
    }

    let modules = packages.flatMap { package in
      package.targets.compactMap { target -> Module? in
        guard let target = target as? SwiftSourceModuleTarget,
              target.kind == .generic || target.kind == .executable
        else { return nil }
        let sourceFiles = target.sourceFiles(withSuffix: "swift")
          .map(\.url.path).sorted()
        guard !sourceFiles.isEmpty else { return nil }
        let dependencies: [String] = target.dependencies.flatMap {
          dependency -> [String] in
          switch dependency {
          case let .target(target):
            target.sourceModule.map { [$0.moduleName] } ?? []
          case let .product(product):
            product.sourceModules.map(\.moduleName)
          @unknown default:
            []
          }
        }
        return Module(
          name: target.moduleName,
          sourceFiles: sourceFiles,
          dependencies: Array(Set(dependencies)).sorted()
        )
      }
    }
    let names = modules.map(\.name)
    guard Set(names).count == names.count else {
      let duplicates = Dictionary(grouping: names, by: { $0 })
        .filter { $0.value.count > 1 }
        .keys.sorted().joined(separator: ", ")
      throw ModuleIndexFailure.duplicateModules(duplicates)
    }
    self.modules = modules.sorted { $0.name < $1.name }
  }

  struct Module: Encodable {
    let name: String
    let sourceFiles: [String]
    let dependencies: [String]
  }
}

private enum ModuleIndexFailure: Error, CustomStringConvertible {
  case duplicateModules(String)

  var description: String {
    switch self {
    case let .duplicateModules(names):
      "SwiftPM resolved more than one target for these module names: \(names)"
    }
  }
}
