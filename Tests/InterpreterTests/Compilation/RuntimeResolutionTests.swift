import BylawsInterpreter
import Testing

@Suite("Portable rule resolution")
struct RuntimeResolutionTests {
  @Test(
    "Rule loading rejects an unsupported receiver member",
    arguments: ReceiverDiagnosticCase.cases
  )
  func receiverAndCallDiagnostics(
    _ testCase: ReceiverDiagnosticCase
  ) async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func invalid(_ declaration: Class) -> Bool {
      \(testCase.expression)
    }

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: .isFinal)
      },
    ]
    """)

    #expect(
      program.errors.contains { $0.message == testCase.message },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Rule loading checks a helper's return type")
  func helperReturnType() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func claimsToReturnBool(_ declaration: Class) -> Bool {
      declaration.name
    }

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: .isFinal)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "'claimsToReturnBool' must return Bool, not String"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Statements after return do not change function return type")
  func statementsAfterReturn() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func isValid(_ declaration: Class) -> Bool {
      return true
      return declaration.name
    }

    let valid = Matcher<Class>("be valid") { isValid($0) }

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: valid)
      },
    ]
    """)

    #expect(program.errors.isEmpty, "\(program.errors.map(\.message))")
    #expect(program.rules.count == 1)
  }

  @Test(
    "Statements after an if that returns from both branches do not change return type"
  )
  func statementsAfterReturningBranches() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func isValid(_ declaration: Class) -> Bool {
      if declaration.isFinal {
        return true
      } else {
        return false
      }
      return declaration.name
    }

    let valid = Matcher<Class>("be valid") { isValid($0) }

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: valid)
      },
    ]
    """)

    #expect(program.errors.isEmpty, "\(program.errors.map(\.message))")
    #expect(program.rules.count == 1)
  }

  @Test("Both if branches must return the declared type")
  func completeBranchesReturnDeclaredType() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func isValid(_ declaration: Class) -> Bool {
      if declaration.isFinal {
        return true
      } else {
        return declaration.name
      }
    }

    let valid = Matcher<Class>("be valid") { isValid($0) }
    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: valid)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "'isValid' must return Bool, not String"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("An early return must use the declared type")
  func earlyBranchReturnsDeclaredType() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func isValid(_ declaration: Class) -> Bool {
      if declaration.isFinal {
        return declaration.name
      }
      return true
    }

    let valid = Matcher<Class>("be valid") { isValid($0) }
    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: valid)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "'isValid' must return Bool, not String"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Rule loading checks a matcher's subject type")
  func matcherSubjectType() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])
    let propertyMatcher = Matcher<Property>("pass") { _ in true }

    let rules: [Rule] = [
      Rule("invalid", "Invalid") {
        app.classes.violations(of: propertyMatcher)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "Matcher<Property> does not apply to Class"
      }
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Rule loading rejects matchers for different types")
  func mixedMatcherSubjects() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])
    let classes = Matcher<Class>("be a class") { _ in true }
    let properties = Matcher<Property>("be a property") { _ in true }
    let invalid = classes && properties

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: invalid)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "'&&' cannot combine Matcher<Class> and Matcher<Property>"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Unsupported type annotations produce a diagnostic")
  func unsupportedTypeAnnotation() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])
    let identifier: UUID = "example"

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: .isFinal)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "portable rules do not support the 'UUID' type"
      },
      "\(program.errors.map(\.message))"
    )
  }

  @Test("Rule loading checks a constructor's generic argument")
  func constructorGenericArgument() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func invalid(_ property: Property) -> Violations<Class> {
      Violations<Class>(
        rule: "be valid",
        offenders: [property],
        checkedCount: 1
      )
    }

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: .isFinal)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "the offenders must be Class, not Property"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Arrays and sets remain distinct types")
  func arrayAndSetAreDistinct() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func invalid(_ declaration: Class) -> Bool {
      Set([declaration.name]) == [declaration.name]
    }

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: .isFinal)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "'==' does not apply to these values"
      }
    )
    #expect(program.rules.isEmpty)
  }

  @Test("A set rejects order-dependent member access")
  func setFirst() async throws {
    let (program, _) = try await diagnostics(forRules: """
    import Bylaws

    let app = Codebase(including: ["Sources/**"])

    func invalid(_ declaration: Class) -> Bool {
      Set([declaration.name]).first == declaration.name
    }

    let rules: [Rule] = [
      Rule("valid", "Valid") {
        app.classes.violations(of: .isFinal)
      },
    ]
    """)

    #expect(
      program.errors.contains {
        $0.message == "'first' is not a supported member of Set"
      },
      "\(program.errors.map(\.message))"
    )
    #expect(program.rules.isEmpty)
  }
}

struct ReceiverDiagnosticCase: Sendable, CustomTestStringConvertible {
  let expression: String
  let message: String

  var testDescription: String { message }

  static let cases = [
    ReceiverDiagnosticCase(
      expression: "declaration.isIndirect",
      message: "'isIndirect' is not a supported member of Class"
    ),
    ReceiverDiagnosticCase(
      expression: "declaration.name(prefix: \"App\")",
      message: "'name' is not callable"
    ),
    ReceiverDiagnosticCase(
      expression: "declaration.functions.contains(value: declaration)",
      message: "'contains' takes arguments (_) or (where:)"
    ),
    ReceiverDiagnosticCase(
      expression: "declaration.functions.contains(declaration.name)",
      message: "argument 1 must be Function, not String"
    ),
  ]
}
