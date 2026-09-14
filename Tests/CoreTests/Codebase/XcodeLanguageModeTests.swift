import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsCore

@Suite("Xcode language settings")
struct XcodeLanguageModeTests {
  @Test("Target mode overrides project setting", arguments: [
    ("5.0", "6.0", SwiftLanguageMode.v5),
    ("6.0", "5.0", .v6),
  ])
  func targetMode(
    target: String,
    project: String,
    expected: SwiftLanguageMode
  ) throws {
    let source = xcodeProjectSource(
      targetSettings: "SWIFT_VERSION = \(target);",
      projectMode: project
    )
    #expect(try XcodeLanguageMode.read(
      source: source,
      path: "/project/App.xcodeproj/project.pbxproj"
    ) == expected)
  }

  @Test("Target inherits project mode")
  func inheritedMode() throws {
    let source = xcodeProjectSource(targetSettings: "", projectMode: "5.0")
    #expect(try XcodeLanguageMode.read(
      source: source,
      path: "/project/App.xcodeproj/project.pbxproj"
    ) == .v5)
  }

  @Test("Unresolved Xcode settings request explicit mode", arguments: [
    "SWIFT_VERSION = \"$(inherited)\";",
    "SWIFT_VERSION = 6.0; \"SWIFT_VERSION[sdk=iphoneos*]\" = 5.0;",
    "SWIFT_VERSION = 6.0; OTHER_SWIFT_FLAGS = \"-swift-version 5\";",
  ])
  func unresolvedSetting(settings: String) {
    #expect(throws: CodebaseError.self) {
      try XcodeLanguageMode.read(
        source: xcodeProjectSource(
          targetSettings: settings,
          projectMode: "6.0"
        ),
        path: "/project/App.xcodeproj/project.pbxproj"
      )
    }
  }

  @Test("Compiler flags unrelated to language mode permit detection")
  func otherFlags() throws {
    let source = xcodeProjectSource(
      targetSettings: "OTHER_SWIFT_FLAGS = (\"-D\", \"DEBUG\");",
      projectMode: "5.0"
    )

    #expect(try XcodeLanguageMode.read(
      source: source, path: "/project/App.xcodeproj/project.pbxproj"
    ) == .v5)
  }

  @Test("Conflicting build configurations request explicit mode")
  func conflictingConfigurations() {
    let source = """
    {
      rootObject = project;
      objects = {
        project = { targets = (app); buildConfigurationList = projectList; };
        app = { isa = PBXNativeTarget; buildConfigurationList = targetList; };
        projectList = { buildConfigurations = (projectDebug, projectRelease); };
        targetList = { buildConfigurations = (debug, release); };
        projectDebug = { name = Debug; buildSettings = {}; };
        projectRelease = { name = Release; buildSettings = {}; };
        debug = { name = Debug; buildSettings = { SWIFT_VERSION = 5.0; }; };
        release = { name = Release; buildSettings = { SWIFT_VERSION = 6.0; }; };
      };
    }
    """

    #expect(throws: CodebaseError.self) {
      try XcodeLanguageMode.read(
        source: source,
        path: "/project/App.xcodeproj/project.pbxproj"
      )
    }
  }
}
