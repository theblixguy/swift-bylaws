import ArgumentParser
import BylawsPaths
import Foundation

struct InitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Writes a Bylaws.swift template.",
    discussion: """
    The template uses advisory rules, so your first run shows the codebase's \
    current behaviour without failing the build.

    Create Bylaws.swift in the current directory and check the template:

        bylaws init
        bylaws lint

    You can write the template elsewhere by passing its path:

        bylaws init --path Config/Bylaws.swift
    """
  )

  @Option(help: "Write the file at this path.")
  var path = "Bylaws.swift"

  @Flag(help: "Replace the file when it exists.")
  var force = false

  func run() async throws {
    guard force || !FileManager.default.fileExists(atPath: path) else {
      throw ValidationError(
        "'\(path)' exists. Pass --force to overwrite it."
      )
    }
    do {
      try RulesFileTemplate.content.write(
        toFile: path,
        atomically: true,
        encoding: .utf8
      )
    } catch {
      try DiagnosticPrinter.printWriteFailure(
        error,
        writing: "'\(path)'",
        rulesFileRoot: LexicalFilePath.currentDirectory.string,
        format: .xcode
      )
      throw ExitCode(2)
    }
    print("""
    Wrote \(path). Run 'bylaws lint' to check the rules.
    Read more rule examples at https://theblixguy.github.io/swift-bylaws/documentation/bylaws/rulecookbook
    """)
  }
}

enum RulesFileTemplate {
  static let content = """
  let app = Codebase(
    including: ["Sources/**"],
    excluding: ["**/*.docc/**"]
  )

  /*
   Public declarations form the package interface, so their purpose should be
   clear without reading the implementation.

   Bad:
   public struct Cart {}

   Good:
   /// A cart containing the products selected for purchase.
   public struct Cart {}
   */
  Rule(
    "public-api-docs",
    "Public types carry documentation",
    enforcement: .advisory,
    hint: "add a doc comment that says what the declaration is for"
  ) {
    app.types.violations(of: !.isPublic || .hasDocumentation)
  }

  /*
   Direct console output bypasses the project's logging and redaction policy.

   Bad:
   print(order)

   Good:
   logger.info("Created order")
   */
  Rule(
    "no-print",
    "Source files do not call print",
    enforcement: .advisory,
    hint: "use the project's logger or remove the call"
  ) {
    app.calls.violations(matching: .references("print"))
  }

  /*
   Most classes in this project are not extension points, so a non-final class
   should be a deliberate exception.

   Bad:
   class HomeScreen {}

   Good:
   final class HomeScreen {}
   */
  Rule(
    "final-classes",
    "Classes are final",
    enforcement: .advisory,
    hint: "mark the class final or exclude a deliberate extension point"
  ) {
    app.classes.violations(of: .isFinal)
  }

  """
}
