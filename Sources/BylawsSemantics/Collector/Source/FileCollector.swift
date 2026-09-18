import BylawsSyntax
import Foundation

/// Parses Swift source from a file or string into ``SourceFile`` models.
public enum FileCollector {
  /// Reads and parses the file at `path`.
  ///
  /// - Throws: ``ParseError/unreadable(path:reason:)`` when the file cannot be
  ///   read, or ``ParseError/didNotParse(diagnostics:)`` when it has a syntax
  ///   error.
  public static func collect(
    fileAt path: String,
    swiftLanguageMode: SwiftLanguageMode = .v6
  ) throws(ParseError)
    -> SourceFile
  {
    let source = try readSource(atPath: path)
    return try collect(
      source: source,
      path: path,
      swiftLanguageMode: swiftLanguageMode
    )
  }

  /// Reads the UTF-8 text of the file at `path`.
  ///
  /// - Throws: ``ParseError/unreadable(path:reason:)`` when the file cannot be
  ///   read or does not hold UTF-8 text.
  public static func readSource(atPath path: String) throws(ParseError)
    -> String
  {
    let bytes = try readBytes(atPath: path)
    guard let source = String(bytes: bytes, encoding: .utf8) else {
      throw .unreadable(path: path, reason: "the file is not UTF-8 text")
    }
    return source
  }

  /// Parses `source` at a virtual `path` without reading from disk.
  ///
  /// - Throws: ``ParseError/didNotParse(diagnostics:)`` when the parser recovers
  ///   from a syntax error. A recovered tree can omit declarations and make
  ///   a rule pass incorrectly.
  public static func collect(
    source: String,
    path: String,
    swiftLanguageMode: SwiftLanguageMode = .v6
  )
    throws(ParseError) -> SourceFile
  {
    let tree = swiftLanguageMode.parse(source)

    if tree.hasError {
      let converter = SourceLocationConverter(fileName: path, tree: tree)
      let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree)
        .filter { $0.diagMessage.severity == .error }
        .map { diagnostic in
          let location = converter.location(for: diagnostic.position)
          return SourceParseDiagnostic(
            location: DeclarationLocation(
              filePath: path, line: location.line, column: location.column,
              utf8Offset: diagnostic.position.utf8Offset
            ),
            message: diagnostic.message,
            swiftLanguageMode: swiftLanguageMode
          )
        }
      throw .didNotParse(diagnostics: diagnostics)
    }

    let visitor = DeclarationVisitor(
      path: path,
      text: SourceText(source: source, swiftLanguageMode: swiftLanguageMode)
    )
    visitor.walk(tree)

    return SourceFile(
      path: path,
      source: visitor.sourceBuffer,
      swiftLanguageMode: swiftLanguageMode,
      imports: visitor.imports,
      classes: visitor.classes,
      actors: visitor.actors,
      structs: visitor.structs,
      enums: visitor.enums,
      protocols: visitor.protocols,
      extensions: visitor.extensions,
      functions: visitor.functions,
      properties: visitor.properties,
      initializers: visitor.initializers,
      typealiases: visitor.typealiases,
      macroExpansions: visitor.macroExpansions
    )
  }

  // Foundation's extended-attribute read is costly at scale.
  package static func readBytes(atPath path: String) throws(ParseError)
    -> [UInt8]
  {
    let descriptor = unsafe open(path, O_RDONLY)
    guard descriptor >= 0 else {
      throw unreadable(path: path, errorNumber: errno)
    }
    defer { close(descriptor) }

    var status = stat()
    guard unsafe fstat(descriptor, &status) == 0 else {
      throw unreadable(path: path, errorNumber: errno)
    }
    let size = Int(status.st_size)
    var bytes = [UInt8](repeating: 0, count: size)
    var filled = 0
    while filled < size {
      // Swift 6.4 rejects the outer unsafe marker required by 6.2 and 6.3.
      #if compiler(>=6.4)
        let count = bytes.withUnsafeMutableBytes { buffer in
          unsafe read(descriptor, buffer.baseAddress! + filled, size - filled)
        }
      #else
        let count = unsafe bytes.withUnsafeMutableBytes { buffer in
          unsafe read(descriptor, buffer.baseAddress! + filled, size - filled)
        }
      #endif
      if count < 0 {
        guard errno == EINTR else {
          throw unreadable(path: path, errorNumber: errno)
        }
        continue
      }
      guard count > 0 else {
        throw unreadable(path: path, errorNumber: EIO)
      }
      filled += count
    }
    return bytes
  }

  private static func unreadable(
    path: String,
    errorNumber: Int32
  ) -> ParseError {
    let code = POSIXErrorCode(rawValue: errorNumber) ?? .EIO
    return .unreadable(
      path: path,
      reason: POSIXError(code).reportableDescription
    )
  }
}
