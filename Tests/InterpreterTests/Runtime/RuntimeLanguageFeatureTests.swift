import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable runtime language features")
struct RuntimeLanguageFeatureTests {
  @Test(
    "Public model APIs have the same names in portable rules",
    arguments: [
      RuntimeModelAPICase(
        testDescription: "Enum API",
        rule: """
        Rule("models", "Model APIs keep their spelling") {
          let enums = try await app.enums
          let valid = Matcher<Enum>("describe generic enum cases") { value in
            value.genericParameters.contains {
              $0.name == "Value" && $0.constraintName == nil
            }
              && value.cases.contains {
                $0.name == "ready"
                  && $0.rawValue == nil
                  && $0.enclosingTypeName == "State"
              }
              && value.sourceRange.lowerBound < value.sourceRange.upperBound
          }
          return enums.violations(of: valid)
        }
        """,
        source: """
        enum State<Value> {
          case ready
        }
        """
      ),
      RuntimeModelAPICase(
        testDescription: "Type reference API",
        rule: """
        Rule("types", "Type references expose their structure") {
          let properties = try await app.properties
          let valid = Matcher<Property>("use a function tuple type") { value in
            guard let type = value.type else { return false }
            return type.isFunction
              && !type.isTuple
              && !type.isExistential
              && !type.isOpaque
              && type.genericArguments.isEmpty
          }
          return properties.violations(of: valid)
        }
        """,
        source: "let transform: (Int) -> String"
      ),
    ]
  )
  func publicModelAPIs(_ testCase: RuntimeModelAPICase) async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(including: ["Sources/**"])

      let rules: [Rule] = [
        \(testCase.rule),
      ]
      """,
      "Sources/App.swift": testCase.source,
    ])

    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.isEmpty)
  }

  @Test("A Rule array can use a helper and a custom matcher")
  func helperAndMatcher() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Tests/ArchitectureTests/ProjectRules.swift": """
      import Bylaws
      import Testing

      nonisolated let app = Codebase(
        root: .automatic(),
        including: ["Sources/**"]
      )

      nonisolated func hasAtMostOneFunction(_ declaration: Class) -> Bool {
        declaration.functions.count <= 1
      }

      nonisolated let isWithinSizeLimit =
        Matcher<Class>("declare at most one function") {
          hasAtMostOneFunction($0)
        }

      nonisolated let projectRules: [Rule] = [
        Rule("class-size", "Classes stay within the size limit") {
          try await app.classes.violations(of: isWithinSizeLimit)
        },
      ]
      """,
      "Sources/App/Classes.swift": """
      class Small {
        func one() {}
      }

      class Large {
        func one() {}
        func two() {}
      }
      """,
    ])

    let program = await RuleProgram.loaded(
      fromFiles: [
        "\(project.rootURL.path)/Tests/ArchitectureTests/ProjectRules.swift",
      ]
    )
    try program.requireNoDiagnostics()
    let rule = try #require(program.rules.first)
    let violations = try await rule.violations()

    #expect(rule.id == "class-size")
    #expect(violations.rule == "declare at most one function")
    #expect(violations.checkedCount == 2)
    #expect(violations.offenders.map(\.name) == ["Large"])
  }

  @Test("A computed invalid name pattern makes the rule fail")
  func computedInvalidNamePattern() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let invalidPattern = "("

      let projectRules: [Rule] = [
        Rule("names", "Class names match the pattern") {
          let classes = try await app.classes
          return try classes.nameMatching(invalidPattern)
            .violations(of: .isFinal)
        },
      ]
      """,
      "Sources/App/Class.swift": "final class Example {}",
    ])

    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect(throws: RuleError.self) {
      try await rule.violations()
    }
  }

  @Test("A top-level value can refer to a later declaration")
  func forwardReferencedBinding() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let maximumFunctions: Int = configuredLimit
      let configuredLimit = 1
      let small = Matcher<Class>("declare at most one function") {
        $0.functions.count <= maximumFunctions
      }

      let projectRules: [Rule] = [
        Rule("forward-reference", "Later declarations are visible") {
          app.classes.violations(of: small)
        },
      ]
      """,
      "Sources/App/Classes.swift": smallAndLargeClasses,
    ])

    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["Large"])
  }

  @Test("Key paths filter and map model values")
  func keyPaths() async throws {
    let project = try rulesProject(
      rules: """
      Rule("docs", "Classes are documented") {
        let classes = try await app.classes
        let documentedNames = classes.filter(\\.isDocumented).map(\\.name)
        let documented = Matcher<Class>("be documented") {
          documentedNames.contains($0.name)
        }
        return classes.violations(of: documented)
      },
      """,
      sources: [
        "Sources/App/Classes.swift": """
        /// Kept.
        class Documented {}
        class Missing {}
        """,
      ]
    )

    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["Missing"])
  }

  @Test("Concurrent rules can use the same matcher")
  func concurrentCapturedMatcher() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let documented = Matcher<Class>("be documented") { $0.isDocumented }

      let projectRules: [Rule] = [
        Rule("docs-a", "Classes are documented A") {
          app.classes.violations(of: documented)
        },
        Rule("docs-b", "Classes are documented B") {
          app.classes.violations(of: documented)
        },
        Rule("docs-c", "Classes are documented C") {
          app.classes.violations(of: documented)
        },
      ]
      """,
      "Sources/App/Class.swift": "class Missing {}",
    ])
    let program = try await loadedProgram(in: project)

    let offenderNames = try await withThrowingTaskGroup(
      of: [String].self,
      returning: [[String]].self
    ) { group in
      for rule in program.rules {
        group.addTask {
          try await rule.violations().offenders.compactMap(\.name)
        }
      }
      var findings: [[String]] = []
      for try await names in group {
        findings.append(names)
      }
      return findings
    }

    #expect(offenderNames.count == 3)
    #expect(offenderNames.allSatisfy { $0 == ["Missing"] })
  }

  @Test(
    "Portable rules evaluate guard bindings, optional chains and if expressions"
  )
  func controlFlowAndOptionals() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])

      func hasConcreteOptionalType(_ property: Property) -> Bool {
        guard let type = property.type else { return false }
        if type.isOptional {
          return property.type?.references("Service") ?? false
        } else {
          return false
        }
      }

      let typed = Matcher<Property>("have an optional Service type") {
        hasConcreteOptionalType($0)
      }

      let projectRules: [Rule] = [
        Rule("types", "Properties use the expected type") {
          app.properties.violations(of: typed)
        },
      ]
      """,
      "Sources/App/Properties.swift": """
      let service: Service?
      let inferred = Service()
      let count: Int
      """,
    ])

    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["inferred", "count"])
  }

  @Test("Optional chaining returns one optional value")
  func optionalChainingFlattens() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let documented = Matcher<Class>("have documentation text") {
        $0.documentation?.first?.description != nil
      }
      let projectRules: [Rule] = [
        Rule("docs", "Classes have documentation text") {
          app.classes.violations(of: documented)
        },
      ]
      """,
      "Sources/App/Classes.swift": """
      /// Present.
      class Documented {}
      class Missing {}
      """,
    ])

    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["Missing"])
  }

  @Test("Integer addition reports overflow")
  func integerAdditionOverflow() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let valid = Matcher<Class>("fit in an integer") { _ in
        9223372036854775807 + 1 > 0
      }
      let projectRules: [Rule] = [
        Rule("integer-range", "Integer arithmetic stays in range") {
          app.classes.violations(of: valid)
        },
      ]
      """,
      "Sources/App/Class.swift": "class Example {}",
    ])

    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.violations()
    } throws: { error in
      String(describing: error)
        .contains("integer addition exceeds the supported range")
    }
  }

  @Test("Large integers compare at full precision")
  func largeIntegerComparison() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let valid = Matcher<Class>("preserve integer precision") { _ in
        9223372036854775807 > 9223372036854775806
      }
      let projectRules: [Rule] = [
        Rule("integer-comparison", "Integer comparisons preserve precision") {
          app.classes.violations(of: valid)
        },
      ]
      """,
      "Sources/App/Class.swift": "class Example {}",
    ])

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
  }

  @Test("Integer negation reports overflow")
  func integerNegationOverflow() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let minimum = -9223372036854775807 + -1
      let valid = Matcher<Class>("negate an integer") { _ in
        -minimum < 0
      }
      let projectRules: [Rule] = [
        Rule("integer-negation", "Integer arithmetic stays in range") {
          app.classes.violations(of: valid)
        },
      ]
      """,
      "Sources/App/Class.swift": "class Example {}",
    ])

    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.violations()
    } throws: { error in
      String(describing: error)
        .contains("integer negation exceeds the supported range")
    }
  }

  @Test("Set equality ignores insertion order")
  func setEquality() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "ProjectRules.swift": """
      import Bylaws

      let app = Codebase(root: .automatic(), including: ["Sources/**"])
      let projectRules: [Rule] = [
        Rule("names", "The expected classes exist") {
          let classes = try await app.classes
          let names = classes.map(\\.name)
          let actual = Set(names)
          let expected = Set(["Second", "First"])
          let matches = Matcher<Class>("belong to the expected set") { _ in
            actual == expected
              && expected.isSubset(of: names)
              && expected.isSubset(of: actual)
          }
          return classes.violations(of: matches)
        },
      ]
      """,
      "Sources/App/Classes.swift": "class First {}\nclass Second {}",
    ])

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.isEmpty)
  }

  @Test("A rule can create violations from a filtered collection")
  func constructsViolations() async throws {
    let project = try rulesProject(
      rules: """
      Rule("size", "Classes stay small") {
        let classes = try await app.classes
        let oversized = classes.filter { $0.functions.count > 1 }
        return Violations(
          rule: "declare at most one function",
          offenders: oversized,
          checkedCount: classes.count
        )
      },
      """,
      sources: [
        "Sources/App/Classes.swift": """
        class Small { func one() {} }
        class Large { func one() {}; func two() {} }
        """,
      ]
    )

    let program = try await loadedProgram(in: project)
    let violations = try await #require(program.rules.first).violations()

    #expect(violations.checkedCount == 2)
    #expect(violations.offenders.map(\.name) == ["Large"])
  }
}

struct RuntimeModelAPICase:
  Codable,
  Sendable,
  CustomTestStringConvertible
{
  let testDescription: String
  let rule: String
  let source: String
}
