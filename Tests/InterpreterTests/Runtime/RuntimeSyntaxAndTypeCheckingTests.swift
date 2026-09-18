import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable syntax and type checking")
struct RuntimeSyntaxAndTypeCheckingTests {
  @Test("Portable rules can count SwiftSyntax members")
  func syntaxMemberCount() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      import BylawsSyntax

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      let projectRules: [Rule] = [
        Rule("members", "Classes stay small") {
          let files = try await app.files
          let classes = try await app.classes
          guard let file = files.first else {
            return Violations(rule: "declare at most one member", offenders: [], checkedCount: 0)
          }
          let small = Matcher<Class>("declare at most one member") { declaration in
            let count = file.withSyntax(
              of: declaration,
              as: ClassDeclSyntax.self
            ) { $0.memberBlock.members.count }
            return (count ?? 0) <= 1
          }
          return classes.violations(of: small)
        },
      ]
      """,
      "Sources/App/Classes.swift": smallAndLargeClasses,
    ])

    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["Large"])
  }

  @Test("SwiftSyntax trivia filter returns comments only")
  func syntaxCommentTrivia() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws
      import SwiftSyntax

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      let hasNoTODO = Matcher<SourceFile>("contain no TODO comment") { file in
        let comments = file.withSyntax { tree in
          Trivia(pieces: tree.tokens(viewMode: .sourceAccurate).flatMap {
            ($0.leadingTrivia + $0.trailingTrivia).filter(\\.isComment)
          }).description
        }
        return !comments.contains("TODO")
      }

      let projectRules: [Rule] = [
        Rule("todos", "Sources contain no TODO comments") {
          app.files.violations(of: hasNoTODO)
        },
      ]
      """,
      "Sources/App/Clean.swift": "let TODOValue = \"TODO\"",
      "Sources/App/Pending.swift": "// TODO: remove this\nlet value = 1",
    ])

    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["Pending.swift"])
  }

  @Test("A matcher closure cannot use await")
  func matcherRejectsSuspension() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func check(_ declaration: Class) async -> Bool { true }

      let invalid = Matcher<Class>("pass") {
        await check($0)
      }

      let projectRules: [Rule] = [
        Rule("invalid", "Invalid") {
          app.classes.violations(of: invalid)
        },
      ]
      """,
      "Sources/App/A.swift": "class A {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/ProjectRules.swift"]
    )

    #expect(
      program.errors.contains {
        $0.message == "this closure must be synchronous and nonthrowing"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("A helper result must match its declared type")
  func helperReturnType() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func claimsToReturnBool(_ declaration: Class) -> Bool {
        declaration.name
      }

      let invalid = Matcher<Class>("pass") {
        claimsToReturnBool($0)
      }

      let projectRules: [Rule] = [
        Rule("invalid", "Invalid") {
          app.classes.violations(of: invalid)
        },
      ]
      """,
      "Sources/App/A.swift": "class A {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/ProjectRules.swift"]
    )

    #expect(
      program.errors.contains {
        $0.message == "'claimsToReturnBool' must return Bool, not String"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Type annotations convert integers, arrays and optional values")
  func typeAnnotationsConvertValues() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func limit(_ count: Int) -> Double { 2 }

      let projectRules: [Rule] = [
        Rule("limits", "Files stay under the limit") {
          let files = try await app.files
          let maximum: Double? = limit(files.count)
          let counts: [Double] = [1]
          let optionalCounts: [Double]? = [1]
          let firstCount: Double? = counts.first
          let underLimit = Matcher<SourceFile>("stay under the limit") { _ in
            (firstCount ?? 0) < (maximum ?? 0) && optionalCounts != nil
          }
          return files.violations(of: underLimit)
        },
      ]
      """,
      "Sources/App/A.swift": "struct A {}",
    ])

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.checkedCount == 1)
    #expect(violations.offenders.isEmpty)
  }

  @Test("A matcher input type must match the selection type")
  func matcherSubjectType() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let propertyMatcher = Matcher<Property>("pass") { _ in true }

      let projectRules: [Rule] = [
        Rule("invalid", "Invalid") {
          app.classes.violations(of: propertyMatcher)
        },
      ]
      """,
      "Sources/App/A.swift": "class A {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/ProjectRules.swift"]
    )

    #expect(
      program.errors.contains {
        $0.message == "Matcher<Property> does not apply to Class"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("A guard failure body must exit its scope")
  func guardFailureMustExit() async throws {
    let program = try await portableProgram(forRules: """
    func hasExplicitType(_ property: Property) -> Bool {
      guard let type = property.type else {
        false
      }
      return type.isOptional
    }

    let typed = Matcher<Property>("have an explicit type") {
      hasExplicitType($0)
    }
    let projectRules: [Rule] = [
      Rule("types", "Properties have explicit types") {
        app.properties.violations(of: typed)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "a guard failure must leave the current scope"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("A guard binding is unavailable in its failure body")
  func guardBindingDoesNotLeak() async throws {
    let program = try await portableProgram(forRules: """
    func hasExplicitType(_ property: Property) -> Bool {
      guard let type = property.type else {
        return type.isOptional
      }
      return type.isOptional
    }

    let typed = Matcher<Property>("have an explicit type") {
      hasExplicitType($0)
    }
    let projectRules: [Rule] = [
      Rule("types", "Properties have explicit types") {
        app.properties.violations(of: typed)
      },
    ]
    """)

    #expect(
      program.errors.contains { $0.message == "'type' is not declared" },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("A filtered selection returns each match once")
  func selectionMatcherFilterDoesNotDuplicateMatches() async throws {
    let project = try rulesProject(
      rules: """
      Rule("final", "Final classes") {
        app.classes.where(.isFinal).violations(matching: .isFinal)
      },
      """,
      sources: [
        "Sources/App/Types.swift": "final class FinalType {}\nclass OpenType {}",
      ]
    )
    let program = try await loadedProgram(in: project)

    let violations = try await #require(program.rules.first).violations()

    #expect(violations.checkedCount == 1)
    #expect(violations.offenders.map(\.name) == ["FinalType"])
  }

  @Test("A recursive helper stops at the call-depth limit")
  func recursiveHelperLimit() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func recursive(_ declaration: Class) -> Bool {
        recursive(declaration)
      }

      let recursiveMatcher = Matcher<Class>("terminate") {
        recursive($0)
      }

      let projectRules: [Rule] = [
        Rule("recursive", "Recursive") {
          app.classes.violations(of: recursiveMatcher)
        },
      ]
      """,
      "Sources/App/A.swift": "class A {}",
    ])
    let program = await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/ProjectRules.swift"]
    )

    let rule = try #require(program.rules.first)
    await #expect {
      try await rule.violations()
    } throws: { error in
      String(describing: error).contains("call-depth limit")
    }
  }

  private func portableProgram(forRules rules: String) async throws
    -> RuleProgram
  {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      \(rules)
      """,
      "Sources/App/A.swift": "let value: Int = 1",
    ])
    return await RuleProgram.loaded(
      fromFiles: ["\(project.rootURL.path)/ProjectRules.swift"]
    )
  }
}
