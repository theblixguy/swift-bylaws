import BylawsSemantics
import Testing

@Suite("Call matching by name and labels")
struct CallSignatureTests {
  init() throws {
    let file = try FileCollector.collect(
      source: """
      struct Screen {
        func build() {
          let logo = UIImage(named: "logo")
          let icon = UIImage(systemName: "star")
          let empty = UIImage()
          save(logo, to: icon)
          Task.detached { }
          Task.detached(priority: .high) { }
          session?.dataTask()
          factory!.make()
        }
      }
      """,
      path: "/virtual/App/Screen.swift"
    )
    build = try #require(file.functions.first)
  }

  @Test("Argument labels separate two forms of one API")
  func labelsSeparateForms() {
    #expect(build.calls("UIImage(named:)"))
    #expect(build.calls("UIImage(systemName:)"))
    #expect(!build.calls("UIImage(title:)"))
  }

  @Test("A call with no arguments matches an empty label list")
  func emptyLabelList() {
    #expect(build.calls("UIImage()"))
    #expect(build.calls("Task.detached()"))
    #expect(build.calls("Task.detached(priority:)"))
  }

  @Test("Parser represents an unlabelled argument with an underscore")
  func unlabelledArgument() {
    #expect(build.calls("save(_:to:)"))
    #expect(!build.calls("save(from:to:)"))
  }

  @Test("Call matching without brackets ignores argument labels")
  func nameWithoutBrackets() {
    #expect(build.calls("UIImage"))
    #expect(build.calls("Task.detached"))
  }

  @Test("Optional and forced calls use their identifier path")
  func optionalAndForcedPaths() throws {
    let optional = try #require(
      build.calls.first { $0.calledExpression == "session?.dataTask" }
    )
    let forced = try #require(
      build.calls.first { $0.calledExpression == "factory!.make" }
    )

    #expect(optional.baseName == "session")
    #expect(optional.memberName == "dataTask")
    #expect(optional.references("session.dataTask"))
    #expect(forced.baseName == "factory")
    #expect(forced.memberName == "make")
    #expect(forced.references("factory.make"))
  }

  private let build: Function
}
