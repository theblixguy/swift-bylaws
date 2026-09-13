import Bylaws
import BylawsTestSupport
import Foundation
import Testing

@Suite("Dependency stability", .tags(.layering))
struct DependencyStabilityTests {
  init() throws {
    project = try TemporaryProject(
      files: [
        "Package.swift": DependencyStabilityMock.manifest(
          toolsVersion: "6.0",
          packageName: "App"
        ),
        "Sources/Logging/Log.swift": "public func log() {}",
        "Sources/Utils/Clamp.swift": "import Logging",
        "Sources/Core/Cart.swift": "import Utils\nstruct Cart {}",
        "Sources/Core/User.swift": "import Utils\nstruct User {}",
        "Sources/Data/Store.swift": "import Core",
        "Sources/UI/HomeView.swift": "import Core",
      ]
    )
  }

  @Test("An edge towards a freer target is a violation")
  func unstableEdgeIsReported() async throws {
    let check = try await codebase.checkDependencyStability()
    let edge = try #require(check.unstable.first)
    #expect(check.unstable.count == 1)
    #expect(edge.target == "Core")
    #expect(edge.importedTarget == "Utils")
    #expect(edge.instability < edge.importedInstability)
    #expect(edge.importedInstability == 0.5)
    #expect(check.checkedEdgeCount == 4)
    #expect(check.violations.offenders == [edge.importDeclaration])
    #expect(check.violations.checkedCount == check.checkedEdgeCount)
  }

  @Test("A dependency edge reports only its first import")
  func repeatedImportReportsOneOffender() async throws {
    let violations = try await codebase.checkDependencyStability().violations
    let offender = try #require(violations.offenders.first)
    #expect(violations.offenders.count == 1)
    #expect(offender.name == "Utils")
    #expect(offender.location.fileName == "Cart.swift")
  }

  @Test("Findings carry the unstable edge and honour the ignore list")
  func findingsHonourTheIgnoreList() async throws {
    let findings = try await codebase.checkDependencyStability()
      .findings(reportedAt: .start(of: "Bylaws.swift"))
    let offender = try #require(findings.violations.offenders.first)
    #expect(findings.violations.offenders.count == 1)
    #expect(offender.location.fileName == "Cart.swift")

    let ignored = try await codebase.checkDependencyStability(
      ignoring: ["Utils"]
    ).findings(reportedAt: .start(of: "Bylaws.swift"))
    #expect(ignored.violations.offenders.isEmpty)
  }

  @Test("An ignored target contributes no edge in either direction")
  func ignoredTargetLeavesTheGraph() async throws {
    let check = try await codebase.checkDependencyStability(
      ignoring: ["Utils"]
    )
    #expect(check.unstable.isEmpty)
    #expect(check.checkedEdgeCount == 2)
  }

  private let project: TemporaryProject

  private var codebase: Codebase {
    Codebase(root: .directory(project.rootURL.path), including: ["Sources/**"])
  }
}
