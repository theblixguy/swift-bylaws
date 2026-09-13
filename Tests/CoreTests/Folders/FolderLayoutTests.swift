import Bylaws
import BylawsTestSupport
import Foundation
import Testing

@Suite("Folder layouts")
struct FolderLayoutTests {
  @Test("The root itself can have a folder layout")
  func rootFolders() async throws {
    let project = try TemporaryProject(files: [
      "Views/A.swift": "struct A {}",
      "Models/B.swift": "struct B {}",
    ])
    let app = Codebase(root: .directory(project.rootURL.path))
    let result = try await app.checkFolderLayout(
      matching: ".",
      containing: ["Views"]
    )
    #expect(result.matchedFolders == ["."])
    #expect(result.missingFolders.isEmpty)
    #expect(result.unexpectedFolders == ["Models"])
  }

  @Test("Source filters do not hide directories from a layout check")
  func sourceFilters() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App/Views/readme.txt": "",
      "Sources/App/Models/A.swift": "this is not Swift",
    ])
    let app = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Nothing/**"],
      excluding: ["Sources/**"]
    )
    let result = try await app.checkFolderLayout(
      matching: "Sources/App",
      containing: ["Views"]
    )
    #expect(result.matchedFolders == ["Sources/App"])
    #expect(result.missingFolders.isEmpty)
    #expect(result.unexpectedFolders == ["Sources/App/Models"])
  }

  @Test("A symbolic link cannot stand in for a required folder")
  func linkedFolder() async throws {
    let project =
      try TemporaryProject(files: ["Sources/App/Models/A.swift": "struct A {}"])
    try FileManager.default.createSymbolicLink(
      at: project.fileURL(for: "Sources/App/Views"),
      withDestinationURL: project.fileURL(for: "Sources/App/Models")
    )
    let app = Codebase(root: .directory(project.rootURL.path))
    let result = try await app.checkFolderLayout(
      matching: "Sources/App",
      containing: ["Models", "Views"]
    )
    #expect(result.missingFolders == ["Sources/App/Views"])
    #expect(result.unexpectedFolders.isEmpty)
  }

  @Test("A missing root fails the check")
  func missingRoot() async throws {
    let project = try TemporaryProject(files: [:])
    let path = project.fileURL(for: "Absent").path
    let app = Codebase(root: .directory(path))
    await #expect(throws: FolderLayoutError
      .unreadableCodebase(.notADirectory(path: path)))
    {
      try await app.checkFolderLayout(matching: ".", containing: ["Views"])
    }
  }

  @Test("Each feature has the required child folders")
  func featureFolders() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App/Orders/Models/Order.swift": "struct Order {}",
      "Sources/App/Orders/Views/OrderView.swift": "struct OrderView {}",
      "Sources/App/Profile/Models/Profile.swift": "struct Profile {}",
      "Sources/App/Profile/Helpers/readme.txt": "",
    ])
    try FileManager.default.createDirectory(
      at: project.fileURL(for: "Sources/App/Orders/ViewModels"),
      withIntermediateDirectories: true
    )
    let app = Codebase(root: .directory(project.rootURL.path))

    let check = try await app.checkFolderLayout(
      matching: "Sources/App/*",
      containing: ["Models", "ViewModels", "Views"]
    )

    #expect(check.matchedFolders == [
      "Sources/App/Orders",
      "Sources/App/Profile",
    ])
    #expect(check.missingFolders == [
      "Sources/App/Profile/ViewModels", "Sources/App/Profile/Views",
    ])
    #expect(check.unexpectedFolders == ["Sources/App/Profile/Helpers"])
  }

  @Test("A module can use role folders without feature folders")
  func moduleFolders() async throws {
    let app = Codebase(root: .sources([
      "Sources/App/Models/Order.swift": "struct Order {}",
      "Sources/App/ViewModels/OrderViewModel.swift": "class OrderViewModel {}",
      "Sources/App/Views/OrderView.swift": "struct OrderView {}",
    ]))
    let check = try await app.checkFolderLayout(
      matching: "Sources/App", containing: ["Models", "ViewModels", "Views"]
    )
    #expect(check.matchedFolders == ["Sources/App"])
    #expect(check.missingFolders.isEmpty)
    #expect(check.unexpectedFolders.isEmpty)
  }

  @Test("A pattern that matches no folder produces a warning")
  func unmatchedPattern() async throws {
    let app = Codebase(root: .sources([:]))
    let check = try await app.checkFolderLayout(
      matching: "Sources/App/*", containing: ["Views"]
    )
    let location = DeclarationLocation.start(of: "/project/Bylaws.swift")
    let findings = check.findings(reportedAt: location)
    #expect(findings.violations.isEmpty)
    #expect(findings.warnings == [Rule.Warning(
      message: "Folder pattern 'Sources/App/*' matched no folders. Check the pattern.",
      location: location
    )])
  }

  @Test("The next check reads empty folder changes")
  func folderChanges() async throws {
    let project =
      try TemporaryProject(files: ["Sources/App/Views/A.swift": "struct A {}"])
    let app = Codebase(root: .directory(project.rootURL.path))
    let before = try await app.checkFolderLayout(
      matching: "Sources/App",
      containing: ["Views"]
    )
    try FileManager.default.createDirectory(
      at: project.fileURL(for: "Sources/App/Extra"),
      withIntermediateDirectories: true
    )
    let after = try await app.checkFolderLayout(
      matching: "Sources/App",
      containing: ["Views"]
    )
    #expect(before.unexpectedFolders.isEmpty)
    #expect(after.unexpectedFolders == ["Sources/App/Extra"])
  }

  @Test("A regular file cannot stand in for a required folder")
  func fileInPlaceOfFolder() async throws {
    let project = try TemporaryProject(files: ["Sources/App/Views": ""])
    let app = Codebase(root: .directory(project.rootURL.path))
    let check = try await app.checkFolderLayout(
      matching: "Sources/App",
      containing: ["Views"]
    )
    #expect(check.missingFolders == ["Sources/App/Views"])
  }

  @Test(
    "Folder names must be single path components",
    arguments: ["", ".", "..", "A/B", "A\\B", "Views*", "View?"]
  )
  func folderNames(name: String) async throws {
    let app = Codebase(root: .sources([:]))
    await #expect(throws: FolderLayoutError.unsupportedFolderName(name)) {
      try await app.checkFolderLayout(
        matching: "Sources/App",
        containing: [name]
      )
    }
  }

  @Test(
    "Folder patterns stay within the root",
    arguments: [
      "",
      "/Sources",
      "../Sources",
      "Sources/../App",
      "Sources\\App",
    ]
  )
  func folderPatterns(pattern: String) async throws {
    let app = Codebase(root: .sources([:]))
    await #expect(throws: FolderLayoutError.unsupportedPattern(pattern)) {
      try await app.checkFolderLayout(matching: pattern, containing: ["Views"])
    }
  }

  @Test("Folder paths cannot contain null characters")
  func nullCharacters() async throws {
    let app = Codebase(root: .sources([:]))
    await #expect(throws: FolderLayoutError.unsupportedPattern("A\0B")) {
      try await app.checkFolderLayout(matching: "A\0B", containing: ["Views"])
    }
    await #expect(throws: FolderLayoutError.unsupportedFolderName("A\0B")) {
      try await app.checkFolderLayout(
        matching: "Sources/App",
        containing: ["A\0B"]
      )
    }
  }
}
