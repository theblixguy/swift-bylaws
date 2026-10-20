import BylawsCore
import BylawsTestSupport
import Foundation
import Testing

@Suite("Swift Testing request loading")
struct SwiftTestingRuleSessionTests {
  @Test("Missing request file reports read failure")
  func missingFile() throws {
    let project = try TemporaryProject(files: [:])
    let file = project.fileURL(for: "request.json")

    #expect {
      try SwiftTestingRuleSession.readRequest(at: file)
    } throws: { error in
      guard let error = error as? SwiftTestingRuleSessionError,
            case let .cannotReadRequest(reason) = error
      else { return false }
      return !reason.isEmpty
    }
  }

  @Test("Malformed request JSON reports read failure", arguments: [
    "{", "{}", #"{"version":"two"}"#,
  ])
  func malformedJSON(contents: String) throws {
    let project = try TemporaryProject(files: ["request.json": contents])
    let file = project.fileURL(for: "request.json")

    #expect {
      try SwiftTestingRuleSession.readRequest(at: file)
    } throws: { error in
      guard let error = error as? SwiftTestingRuleSessionError,
            case let .cannotReadRequest(reason) = error
      else { return false }
      return !reason.isEmpty
    }
  }

  @Test("Unsupported request version retains version error", arguments: [
    -1, 0, 2, 99,
  ])
  func unsupportedVersion(version: Int) throws {
    let project = try TemporaryProject(files: [:])
    let file = project.fileURL(for: "request.json")
    let request = SwiftTestingRuleSession(
      id: "run", directory: "/reports", rootPath: "/project"
    )
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(request)
    ) as? [String: Any])
    payload["version"] = version
    try JSONSerialization.data(withJSONObject: payload).write(to: file)

    #expect(throws: SwiftTestingRuleSessionError.unsupportedVersion(version)) {
      try SwiftTestingRuleSession.readRequest(at: file)
    }
  }

  @Test("Request rejects empty ID and relative or empty paths", arguments: [
    ("", "/reports", "/project"),
    ("run", "reports", "/project"),
    ("run", "", "/project"),
    ("run", "/reports", "project"),
    ("run", "/reports", ""),
  ])
  func malformedRequest(
    id: String,
    directory: String,
    rootPath: String
  ) throws {
    let project = try TemporaryProject(files: [:])
    let file = project.fileURL(for: "request.json")
    let request = SwiftTestingRuleSession(
      id: id, directory: directory, rootPath: rootPath
    )
    try JSONEncoder().encode(request).write(to: file)

    #expect(throws: SwiftTestingRuleSessionError.malformedRequest) {
      try SwiftTestingRuleSession.readRequest(at: file)
    }
  }

  @Test(
    "Valid request preserves session and correction flags",
    arguments: [false, true],
    [false, true]
  )
  func validRequest(isCorrection: Bool, sourceOnly: Bool) throws {
    let project = try TemporaryProject(files: [:])
    let file = project.fileURL(for: "request.json")
    let request = SwiftTestingRuleSession(
      id: "run", directory: project.fileURL(for: "reports").path,
      rootPath: project.rootURL.path,
      isCorrection: isCorrection, sourceOnly: sourceOnly
    )
    try JSONEncoder().encode(request).write(to: file)

    let session = try SwiftTestingRuleSession.readRequest(at: file)

    #expect(session == request)
  }
}
