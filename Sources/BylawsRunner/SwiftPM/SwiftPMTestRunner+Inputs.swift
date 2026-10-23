import BylawsCore
import Foundation

extension SwiftPMTestRunner {
  @concurrent
  static func captureInputs(
    atRoot rootPath: String, directory: URL, scratch: URL?,
    swiftPMArguments: [String], environment: [String: String],
    sessionID: String?
  ) async throws -> [SourceCapture.Record] {
    let result = try await SwiftPMCommand.run(
      arguments: ["package"] + swiftPMArguments
        + ["--package-path", rootPath, "show-dependencies", "--format", "json"],
      rootPath: rootPath, directory: directory, environment: environment
    )
    let graph = try decodeOutput(
      Dependency.self, from: result, atRoot: rootPath
    )
    var roots: Set<String> = []
    func include(_ package: Dependency) throws {
      guard package.path.hasPrefix("/") else {
        throw SwiftTestingRuleSessionError.malformedRequest
      }
      let root = URL(fileURLWithPath: package.path)
        .standardizedFileURL.resolvingSymlinksInPath().path
      roots.insert(root)
      for dependency in package.dependencies { try include(dependency) }
    }
    try include(graph)
    var captures: [SourceCapture.Record] = []
    for root in roots.sorted() {
      captures.append(try await SourceCapture.capture(
        SourceCapture.Scope(
          rootPath: root,
          selection: .sourceFiles(
            including: ["**"],
            excluding: sourceExclusions(atRoot: root, scratch: scratch),
            swiftPM: true, xcode: false
          )
        ), sessionID: sessionID
      ))
    }
    return captures
  }

  static func sourceExclusions(
    atRoot rootPath: String,
    scratch: URL?
  ) -> [String] {
    var exclusions = ["**/.build/**", "**/.git/**"]
    let prefix = URL(fileURLWithPath: rootPath).standardizedFileURL.path + "/"
    if let scratch, scratch.standardizedFileURL.path.hasPrefix(prefix) {
      exclusions
        .append(String(scratch.standardizedFileURL.path
            .dropFirst(prefix.count)) + "/**")
    }
    return exclusions
  }

  private struct Dependency: Decodable {
    let path: String
    let dependencies: [Dependency]
  }
}
