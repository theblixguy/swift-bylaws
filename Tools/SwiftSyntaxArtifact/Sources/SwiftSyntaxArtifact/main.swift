import ArgumentParser
import Foundation
import SwiftSyntaxArtifactCore

@main
struct SwiftSyntaxArtifact: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swift-syntax-artifact",
    abstract: "Builds the SwiftSyntax artifacts used by Bylaws.",
    subcommands: [Prepare.self, Combine.self]
  )

  struct Prepare: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Prepares private SwiftSyntax modules for a framework build."
    )

    @Argument(help: "SwiftSyntax source checkout.")
    var source: String

    @Argument(help: "Directory for the prepared package.")
    var output: String

    mutating func run() throws {
      try SourcePackagePreparer().prepare(
        source: fileURL(source),
        output: fileURL(output)
      )
    }
  }

  struct Combine: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Creates the SwiftSyntax artifacts used by Bylaws."
    )

    @Argument(help: "Directory that contains the module frameworks.")
    var frameworks: String

    @Argument(help: "Prepared SwiftSyntax package.")
    var sourcePackage: String

    @Argument(help: "Directory for the completed artifacts.")
    var output: String

    mutating func run() throws {
      try XCFrameworkCombiner().combine(
        frameworks: fileURL(frameworks),
        sourcePackage: fileURL(sourcePackage),
        output: fileURL(output)
      )
    }
  }

  private static func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path).standardizedFileURL
  }
}
