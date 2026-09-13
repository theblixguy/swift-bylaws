import BylawsCore
import BylawsInterpreter
import BylawsRunner
import BylawsSemantics
import Foundation

struct SARIFLog: Encodable {
  let version = "2.1.0"
  let schema = """
  https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/\
  schema/sarif-schema-2.1.0.json
  """
  let runs: [Run]

  enum CodingKeys: String, CodingKey {
    case version
    case schema = "$schema"
    case runs
  }

  struct Run: Encodable {
    let tool: Tool
    let results: [Result]
    let invocations: [Invocation]
  }

  struct Tool: Encodable {
    let driver: Driver
  }

  struct Driver: Encodable {
    let name = "Bylaws"
    let informationUri = "https://github.com/theblixguy/swift-bylaws"
    let version: String
    let rules: [ReportingDescriptor]
  }

  struct ReportingDescriptor: Encodable {
    let id: String
    let name: String
    let shortDescription: Message
    let fullDescription: Message?
    let defaultConfiguration: Configuration
  }

  struct Configuration: Encodable {
    let level: String
  }

  struct Result: Encodable {
    let ruleId: String
    let ruleIndex: Int
    let level: String
    let message: Message
    let locations: [Location]
  }

  struct Message: Encodable {
    let text: String
  }

  struct Location: Encodable {
    let physicalLocation: PhysicalLocation
  }

  struct PhysicalLocation: Encodable {
    let artifactLocation: ArtifactLocation
    let region: Region
  }

  struct ArtifactLocation: Encodable {
    let uri: String
  }

  struct Region: Encodable {
    let startLine: Int
    let startColumn: Int
  }

  struct Invocation: Encodable {
    let executionSuccessful: Bool
    let toolExecutionNotifications: [Notification]
  }

  struct Notification: Encodable {
    let level: String
    let message: Message
    let locations: [Location]
  }
}

extension SARIFLog {
  init(document: ReportDocument, rootPath: String) {
    func location(of declaration: DeclarationLocation) -> Location {
      Location(physicalLocation: PhysicalLocation(
        artifactLocation: ArtifactLocation(
          uri: Self.uri(of: declaration.filePath, relativeTo: rootPath)
        ),
        region: Region(
          startLine: declaration.line,
          startColumn: declaration.column
        )
      ))
    }

    let descriptors = document.rules.map { rule in
      ReportingDescriptor(
        id: rule.id,
        name: rule.name,
        shortDescription: Message(text: rule.name),
        fullDescription: rule.hint.map(Message.init(text:)),
        defaultConfiguration: Configuration(level: rule.level.compilerName)
      )
    }
    let results = document.events.compactMap { event -> Result? in
      guard event.category != .diagnostic,
            let ruleID = event.ruleID,
            let ruleIndex = event.ruleIndex
      else { return nil }
      return Result(
        ruleId: ruleID,
        ruleIndex: ruleIndex,
        level: event.level.compilerName,
        message: Message(text: event.messageWithoutRuleID),
        locations: [location(of: event.location)]
      )
    }
    let notifications = document.events.compactMap { event -> Notification? in
      guard event.category == .diagnostic else { return nil }
      return Notification(
        level: event.level.compilerName,
        message: Message(text: event.messageWithoutRuleID),
        locations: [location(of: event.location)]
      )
    }

    runs = [Run(
      tool: Tool(driver: Driver(
        version: BylawsVersion.current,
        rules: descriptors
      )),
      results: results,
      invocations: [Invocation(
        executionSuccessful: !document.events.contains {
          $0.category == .diagnostic && $0.level == .error
        },
        toolExecutionNotifications: notifications
      )]
    )]
  }

  var rendered: String {
    get throws {
      try renderReportJSON(self)
    }
  }

  private static func uri(of path: String, relativeTo rootPath: String)
    -> String
  {
    guard let relativePath = ReportPath.relative(path, to: rootPath) else {
      return URL(fileURLWithPath: path).absoluteString
    }
    var allowedCharacters = CharacterSet.urlPathAllowed
    allowedCharacters.remove(charactersIn: "%?#:")
    return relativePath.addingPercentEncoding(
      withAllowedCharacters: allowedCharacters
    ) ?? relativePath
  }
}
