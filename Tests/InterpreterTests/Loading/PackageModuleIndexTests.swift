import BylawsInterpreter
import Testing

@Suite("SwiftPM module index")
struct PackageModuleIndexTests {
  @Test(
    "Invalid module error includes the invalid name or path",
    arguments: [
      InvalidModuleIndexCase(
        modules: [.init(
          name: "",
          sourceFiles: ["Rules.swift"],
          dependencies: []
        )],
        message: "the module containing 'Rules.swift' has an empty name"
      ),
      InvalidModuleIndexCase(
        modules: [
          .init(name: "Rules", sourceFiles: ["First.swift"], dependencies: []),
          .init(name: "Rules", sourceFiles: ["Second.swift"], dependencies: []),
        ],
        message: "module name 'Rules' appears more than once"
      ),
      InvalidModuleIndexCase(
        modules: [.init(name: "Rules", sourceFiles: [], dependencies: [])],
        message: "module 'Rules' has no source files"
      ),
      InvalidModuleIndexCase(
        modules: [.init(
          name: "Rules",
          sourceFiles: ["Rules.txt"],
          dependencies: []
        )],
        message: "module 'Rules' has an empty or non-Swift source path: 'Rules.txt'"
      ),
    ]
  )
  func invalidModuleIdentifiesContext(_ testCase: InvalidModuleIndexCase) {
    #expect {
      try PackageModuleIndex(modules: testCase.modules)
    } throws: { error in
      String(describing: error) == testCase.message
    }
  }
}

struct InvalidModuleIndexCase: Codable, Sendable, CustomTestStringConvertible {
  let modules: [PackageModuleIndex.Module]
  let message: String

  var testDescription: String { message }
}
