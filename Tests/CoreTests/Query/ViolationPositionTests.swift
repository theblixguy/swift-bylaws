import Bylaws
import Testing

@Suite("Violation source locations")
struct ViolationPositionTests {
  private static let codebase = Codebase(root: .sources([
    "Sources/Reporter.swift": """
    struct Reporter {
      func report() {
        print("done")
      }
    }
    """,
    "Sources/Legacy.swift": """
    // The compatibility shim.
    import Legacy

    class Shim {}
    """,
  ]))

  @Test("Banned call reports call location")
  func bannedCall() async throws {
    let violations = try await Self.codebase.files
      .named("Reporter.swift")
      .violations(matching: .calls("print"))
      .erased()

    let offender = try #require(violations.offenders.first)
    #expect(offender.description == "Reporter.swift")
    #expect(offender.location.line == 3)
  }

  @Test("Banned import reports import location")
  func bannedImport() async throws {
    let violations = try await Self.codebase.files
      .named("Legacy.swift")
      .violations(matching: .imports("Legacy"))
      .erased()

    let offender = try #require(violations.offenders.first)
    #expect(offender.location.line == 2)
  }

  @Test("Combined matcher reports location of failed condition")
  func decidingRequirement() async throws {
    let violations = try await Self.codebase.functions
      .violations(of: .calls("print") && .isPublic)
      .erased()

    let offender = try #require(violations.offenders.first)
    #expect(offender.description == "report()")
    #expect(offender.location.line == 2)
  }

  @Test("Declaration rule reports declaration location")
  func declarationRule() async throws {
    let violations = try await Self.codebase.classes
      .violations(of: .isFinal)
      .erased()

    let offender = try #require(violations.offenders.first)
    #expect(offender.description == "Shim")
    #expect(offender.location.line == 4)
  }
}
