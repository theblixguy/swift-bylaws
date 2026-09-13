import BylawsPaths
import BylawsSemantics
import Foundation

/// The recorded violations that a rule set accepts as existing debt.
///
/// A baseline is a generated Swift file in the test target. Declare
/// an empty one, run the suite once with `.record`, then remove `.record`
/// and run again:
///
/// ```swift
/// extension Baseline {
///   static let app = Baseline("app", entries: [])
/// }
/// ```
///
/// A rule opts in with the `.baseline(_:mode:)` trait. Known violations remain
/// visible without failing the run, and new violations fail. A recording run
/// rewrites the file with what it observed.
///
/// One entry names one declaration that one rule accepts. With
/// `.annotatesViolations`, a parameterised rule records the declaration for
/// its case. Same-file violations remain independent when one is fixed.
///
/// Without that trait, a rule records only the file. All its violations in the
/// file share one entry. Prefer parameterised rules with
/// `.annotatesViolations` when using a baseline.
public struct Baseline: Sendable, Hashable {
  /// One accepted violation.
  ///
  /// The entry names the rule and the declaration it accepts. Line numbers
  /// are omitted. Edits above the declaration do not invalidate the entry.
  public struct Entry: Sendable, Hashable, Comparable {
    /// The rule the violation belongs to.
    ///
    /// Discovered rules use their IDs as keys. Rules written in code use their
    /// tests' display names.
    public let rule: Rule.ID

    /// The name of the declaration the rule accepts, or an empty string
    /// when the run could not identify one.
    public let declaration: String

    /// The project-relative path of the file or folder the violation concerns.
    ///
    /// An absolute path is retained when no project root is known.
    public let file: String

    /// Creates an entry from a rule name, a declaration name and a file.
    public init(rule: Rule.ID, declaration: String, file: String) {
      self.rule = rule
      self.declaration = declaration
      self.file = file
    }

    package init(
      offender: Offender,
      for rule: Rule.ID,
      relativeTo rootPath: String?
    ) {
      self.init(
        offender: offender,
        for: rule,
        at: offender.affectedPath ?? offender.location.filePath,
        relativeTo: rootPath
      )
    }

    package init(
      offender: Offender,
      for rule: Rule.ID,
      at filePath: String,
      relativeTo rootPath: String?
    ) {
      self.init(
        rule: rule,
        declaration: offender.name ?? "",
        file: Self.fileIdentity(
          for: filePath,
          relativeTo: rootPath
        )
      )
    }

    package static func fileIdentity(
      for filePath: String,
      relativeTo rootPath: String?
    ) -> String {
      let file = filePath.replacing("\\", with: "/")
      guard let rootPath, !rootPath.isEmpty else { return file }
      // Relative paths outside the root can collide with in-root baseline keys.
      let root = LexicalFilePath(rootPath.replacing("\\", with: "/"))
      return LexicalFilePath(file).relative(to: root)?.string ?? file
    }

    public static func < (lhs: Entry, rhs: Entry) -> Bool {
      (lhs.rule.rawValue, lhs.file, lhs.declaration)
        < (rhs.rule.rawValue, rhs.file, rhs.declaration)
    }

    /// The declaration and file as they appear in a baseline message.
    public var acceptedDescription: String {
      declaration.isEmpty ? file : "\(declaration) (\(file))"
    }
  }

  /// The baseline's name.
  ///
  /// Recording regenerates the declaration using this value. Use an ASCII
  /// Swift identifier that matches the declaring property's name. An invalid
  /// name stops the write and reports an error.
  public let name: String

  /// The accepted violations.
  public let entries: [Entry]

  /// The path of the file that declares the baseline.
  ///
  /// Keep the baseline declaration as the file's only content. Recording
  /// replaces the entire file.
  public let file: String

  /// Creates a baseline from its name and entries.
  public init(
    _ name: String,
    entries: [Entry],
    file: String = #filePath
  ) {
    self.name = name
    self.entries = entries
    self.file = file
  }
}
