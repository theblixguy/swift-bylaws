import Testing
@testable import BylawsCore

@Suite("Rule dependencies")
struct RuleDependencyTests {
  @Test("Source scopes match included Swift files")
  func includedSource() {
    let dependency = sourceFiles(
      including: ["Sources/**"],
      excluding: ["Sources/Generated/**"]
    )

    #expect(dependency.contains(path: "/project/Sources/App/App.swift"))
    #expect(!dependency.contains(path: "/project/Sources/Generated/API.swift"))
    #expect(!dependency.contains(path: "/project/README.md"))
  }

  @Test("Automatic SwiftPM mode matches package manifests")
  func swiftPackageManifest() {
    let dependency = sourceFiles(discoversSwiftPackages: true)

    #expect(dependency.contains(path: "/project/Package.swift"))
    #expect(dependency.contains(path: "/project/Packages/UI/Package.swift"))
  }

  @Test("Automatic Xcode mode matches root project settings")
  func xcodeProjectSettings() {
    let dependency = sourceFiles(discoversXcodeProjects: true)

    #expect(dependency.contains(
      path: "/project/App.xcodeproj/project.pbxproj"
    ))
    #expect(!dependency.contains(
      path: "/project/Projects/App.xcodeproj/project.pbxproj"
    ))
  }

  @Test("File dependencies match one path")
  func file() {
    let dependency = RuleDependency.file("/project/graph.json")

    #expect(dependency.contains(path: "/project/graph.json"))
    #expect(!dependency.contains(path: "/project/other.json"))
  }

  @Test("Directory dependencies match descendants")
  func descendants() {
    let dependency = RuleDependency.descendants("/project/Features")

    #expect(dependency.contains(path: "/project/Features/Orders/View.swift"))
    #expect(!dependency.contains(path: "/project/Shared/Date.swift"))
  }

  @Test("Root dependencies match nested project markers")
  func rootMarkers() {
    let dependency = RuleDependency.rootMarkers("/project")

    #expect(dependency.contains(path: "/project/Feature/Package.swift"))
    #expect(dependency.contains(
      path: "/project/Feature/App.xcodeproj/project.pbxproj"
    ))
    #expect(!dependency.contains(path: "/project/Feature/App.swift"))
  }

  @Test("Tracking combines dependencies from child tasks")
  func concurrentTracking() async {
    let tracked = await RuleDependencyTracking.collecting {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          await RuleDependencyTracking.record(.file("/project/First.swift"))
        }
        group.addTask {
          await RuleDependencyTracking.record(.file("/project/Second.swift"))
        }
      }
    }

    #expect(tracked.dependencies == [
      .file("/project/First.swift"),
      .file("/project/Second.swift"),
    ])
    #expect(tracked.isComplete)
  }

  @Test("Untracked inputs mark dependency collection as incomplete")
  func incompleteTracking() async {
    let tracked = await RuleDependencyTracking.collecting {
      await RuleDependencyTracking.recordUntrackedDependency()
    }

    #expect(!tracked.isComplete)
  }

  private func sourceFiles(
    including: [String] = [],
    excluding: [String] = [],
    discoversSwiftPackages: Bool = false,
    discoversXcodeProjects: Bool = false
  ) -> RuleDependency {
    .sourceFiles(RuleDependency.SourceScope(
      rootPath: "/project",
      including: including,
      excluding: excluding,
      discoversSwiftPackages: discoversSwiftPackages,
      discoversXcodeProjects: discoversXcodeProjects
    ))
  }
}
