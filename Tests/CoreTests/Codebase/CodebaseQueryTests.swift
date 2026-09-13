import Bylaws
import BylawsTestSupport
import Foundation
import SwiftSyntax
import Testing

@Suite("Codebase queries")
struct CodebaseQueryTests {
  @Test("All sample app classes are discovered, including nested ones")
  func discoversAllClasses() async throws {
    let classes = try await Codebase.sampleApp.classes
    #expect(classes.map(\.name).sorted() == [
      "BaseViewModel", "Helper", "HomeViewModel", "SettingsViewModel",
    ])
  }

  @Test("Concurrent category queries share one projection")
  func sharesCategoryProjection() async throws {
    async let first = Codebase.sampleApp.functions
    async let second = Codebase.sampleApp.functions

    let selections = try await (first, second)

    #expect(selections.0.storage === selections.1.storage)
  }

  @Test("A completed category query releases its projection")
  func releasesCategoryProjection() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/App.swift": "func run() {}",
    ]))
    weak var storage: SelectionStorage<Function>?
    var selection: Selection<Function>? = try await codebase.functions

    storage = selection?.storage
    #expect(storage != nil)

    selection = nil
    #expect(storage == nil)
  }

  @Test("Actors are discovered with their members")
  func discoversActors() async throws {
    let sessionStore = try #require(
      try await Codebase.sampleApp.actors.named("SessionStore").first
    )
    #expect(sessionStore.functions.map(\.name) == ["begin"])
    #expect(sessionStore.properties.map(\.name) == ["startCount"])
  }

  @Test("Composed filters produce a readable query description")
  func composesFilters() async throws {
    let viewModels = try await Codebase.sampleApp.classes
      .suffixed("ViewModel")
      .excluding("BaseViewModel")

    #expect(viewModels.count == 2)
    #expect(viewModels.queryDescription.contains("suffixed 'ViewModel'"))
    #expect(viewModels.queryDescription.contains("excluding"))
  }

  @Test("Path filters narrow to a directory, with or without a trailing slash")
  func filtersByDirectory() async throws {
    let expected = [
      "Analytics.swift", "Formatting.swift", "Persistence.swift",
      "SessionStore.swift",
    ]
    let supportFiles = try await Codebase.sampleApp.files
      .under("Sources/App/Support")
    #expect(supportFiles.map(\.name).sorted() == expected)

    let trailingSlash = try await Codebase.sampleApp.files
      .under("Sources/App/Support/")
    #expect(trailingSlash.map(\.name).sorted() == expected)
  }

  @Test("Parent paths cannot leave the codebase root")
  func parentPathsCannotLeaveRoot() async throws {
    let files = try await Codebase.sampleApp.files

    #expect(files.under("..").isEmpty)
    #expect(files.outside("..").count == files.count)
  }

  @Test("Calls resolve to their declaring context")
  func findsCallers() async throws {
    let userDefaultsCallers = try await Codebase.sampleApp.functions
      .where(.calls("UserDefaults"))
    #expect(userDefaultsCallers.map(\.name).sorted() == ["markSeen", "reset"])
    #expect(Set(userDefaultsCallers.map(\.enclosingTypeName)) ==
      ["PreferencesStore"])

    let callingFiles = try await Codebase.sampleApp.files
      .where(.calls("UserDefaults"))
    #expect(callingFiles.map(\.name) == ["Persistence.swift"])
  }

  @Test("Direct syntax access returns the declaration's syntax node")
  func directSyntaxAccess() async throws {
    let file = try #require(
      try await Codebase.sampleApp.files.named("HomeViewModel.swift").first
    )
    let home = try #require(file.classes.first)

    let memberCount = file
      .withSyntax(of: home, as: ClassDeclSyntax.self) { node in
        node.memberBlock.members.count
      }
    #expect(memberCount == 1)
  }

  @Test("Syntax lookup rejects a declaration from another file")
  func syntaxLookupRejectsAnotherFile() throws {
    let first = try FileCollector.collect(
      source: "struct First {}",
      path: "/virtual/First.swift"
    )
    let second = try FileCollector.collect(
      source: "struct Second {}",
      path: "/virtual/Second.swift"
    )
    let declaration = try #require(second.structs.first)

    let name = first.withSyntax(
      of: declaration,
      as: StructDeclSyntax.self,
      { $0.name.text }
    )

    #expect(name == nil)
  }

  @Test("Key-path filters narrow selections")
  func filtersByKeyPath() async throws {
    let finalClasses = try await Codebase.sampleApp.classes.where(\.isFinal)
    #expect(finalClasses.map(\.name).sorted() == [
      "HomeViewModel",
      "SettingsViewModel",
    ])
  }

  @Test("Excluding globs remove files from the codebase")
  func excludesGlobbedFiles() async throws {
    let codebase = Codebase(
      root: Codebase.sampleApp.root,
      excluding: ["**/Support/**"]
    )
    let classes = try await codebase.classes
    #expect(!classes.map(\.name).contains("Helper"))
  }

  @Test("Missing root throws a typed error")
  func missingRootThrows() async {
    let codebase = Codebase(root: .directory("/nonexistent/path"))
    await #expect(throws: CodebaseError
      .notADirectory(path: "/nonexistent/path"))
    {
      try await codebase.prepare()
    }
  }

  @Test("A failed parse is not cached forever")
  func failedParseRetries() async throws {
    let directory = NSTemporaryDirectory() + "bylaws-retry-\(UUID().uuidString)"
    let codebase = Codebase(root: .directory(directory))

    await #expect(throws: CodebaseError.self) {
      try await codebase.prepare()
    }

    try FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(atPath: directory) }

    try await codebase.prepare()
    #expect(try await codebase.files.isEmpty)
  }

  @Test("A relative root resolves from the working directory")
  func relativeRootResolvesFromWorkingDirectory() async throws {
    let relativeRoot = ".build/bylaws-relative-\(UUID().uuidString)"
    let absoluteRoot = FileManager.default.currentDirectoryPath
      + "/\(relativeRoot)"
    try FileManager.default.createDirectory(
      atPath: absoluteRoot,
      withIntermediateDirectories: true
    )
    try "struct App {}".write(
      toFile: "\(absoluteRoot)/App.swift",
      atomically: true,
      encoding: .utf8
    )
    defer { try? FileManager.default.removeItem(atPath: absoluteRoot) }

    let files = try await Codebase(root: .directory(relativeRoot)).files

    #expect(files.map(\.path) == ["\(absoluteRoot)/App.swift"])
  }

  @Test("Symlinked roots resolve consistently")
  func symlinkedRootResolves() async throws {
    let directory = NSTemporaryDirectory() + "bylaws-symlink-\(UUID().uuidString)"
    let alias = directory + "-alias"
    try FileManager.default.createDirectory(
      atPath: directory + "/Sources", withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      atPath: alias, withDestinationPath: directory
    )
    defer {
      try? FileManager.default.removeItem(atPath: alias)
      try? FileManager.default.removeItem(atPath: directory)
    }
    try "struct TempThing {}".write(
      toFile: directory + "/Sources/TempThing.swift", atomically: true,
      encoding: .utf8
    )

    let codebase = Codebase(
      root: .directory(alias),
      including: ["Sources/**"]
    )
    let structs = try await codebase.structs
    #expect(structs.map(\.name) == ["TempThing"])

    let files = try await codebase.files.under("Sources")
    #expect(files.count == 1)
  }

  @Test("Declarations render as a name, file and line")
  func rendersDeclarationDescriptions() async throws {
    let home = try #require(
      try await Codebase.sampleApp.classes.named("HomeViewModel").first
    )
    #expect("\(home)" == "HomeViewModel (HomeViewModel.swift:1)")
  }
}
