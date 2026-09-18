import ArgumentParser
import Foundation
import SwiftSyntaxArtifactCore

@main
struct SwiftSyntaxArtifact: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swift-syntax-artifact",
    abstract: "Builds the SwiftSyntax XCFramework used by Bylaws.",
    subcommands: [Prepare.self, Combine.self]
  )

  struct Prepare: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Prepares private SwiftSyntax modules for a framework build."
    )

    @Argument(help: "Artifact configuration file.")
    var configuration: String

    @Argument(help: "SwiftSyntax source checkout.")
    var source: String

    @Argument(help: "Directory for the prepared package.")
    var output: String

    mutating func run() throws {
      let configuration = try ArtifactConfiguration.load(
        from: fileURL(configuration)
      )
      try SourcePackagePreparer(configuration: configuration).prepare(
        source: fileURL(source),
        output: fileURL(output)
      )
    }
  }

  struct Combine: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Combines the module frameworks into one XCFramework."
    )

    @Argument(help: "Artifact configuration file.")
    var configuration: String

    @Argument(help: "Directory that contains the module frameworks.")
    var frameworks: String

    @Argument(help: "Prepared SwiftSyntax package.")
    var sourcePackage: String

    @Argument(help: "Path for the combined XCFramework.")
    var output: String

    mutating func run() throws {
      let configuration = try ArtifactConfiguration.load(
        from: fileURL(configuration)
      )
      try XCFrameworkCombiner(configuration: configuration).combine(
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
