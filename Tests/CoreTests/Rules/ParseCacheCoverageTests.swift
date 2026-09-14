import Bylaws
import Testing

@Suite("Bylaws' parse cache", .codebase(.bylaws), .tags(.layering))
struct ParseCacheCoverageTests {
  @Test("Cache encoders cover stored model fields")
  func encodersCoverEveryModelField() async throws {
    let initializers = try await Codebase.bylaws.initializers
    let encoders = try await Codebase.bylaws.functions
      .filter {
        $0.name == "encode"
          && $0.location.fileName.hasPrefix(Self.encoderFilePrefix)
      }
    try #require(!encoders.isEmpty)

    for encoder in encoders {
      let typeName = try #require(encoder.enclosingTypeName)
      guard !Self.typesWrittenAsOneValue.contains(typeName) else { continue }

      let widest = try #require(
        initializers
          .filter {
            $0.enclosingTypeName == typeName
              && !$0.parameters
              .contains { $0.type.name == Self.decoderTypeName }
          }
          .max { $0.parameters.count < $1.parameters.count },
        "\(typeName) declares no initialiser to check the encoder against"
      )
      let fields = Set(widest.parameters.map { $0.label ?? $0.name })
      let unwritten = fields
        .subtracting(Self.fields(written: encoder, among: encoders))
        .subtracting(Self.rebuiltFields)

      #expect(
        unwritten.isEmpty,
        """
        \(typeName) does not encode \
        \(unwritten.sorted().joined(separator: ", ")), \
        so the parse cache drops \(unwritten.count == 1 ? "it" : "them").
        """,
        sourceLocation: encoder.testingLocation
      )
    }
  }

  private static func fields(
    written encoder: Function,
    among encoders: [Function]
  ) -> Set<String> {
    var written = Set<String>()
    for call in encoder.calls where call.baseName == "encoder" {
      for argument in call.arguments {
        let field = String(argument.text.prefix { $0.isLetter || $0.isNumber })
        written.insert(field)
        if field == Self.storageField,
           let storageEncoder = encoders.first(where: {
             $0.enclosingTypeName == Self.storageTypeName
           })
        {
          written.formUnion(fields(written: storageEncoder, among: []))
        }
      }
    }
    return written
  }

  private static let encoderFilePrefix = "CacheCodable+"
  private static let decoderTypeName = "CacheDecoder"
  private static let storageField = "storage"
  private static let storageTypeName = "NominalTypeStorage"

  private static let rebuiltFields: Set<String> = ["source", "filePath", "path"]

  private static let typesWrittenAsOneValue: Set<String> = ["Visibility"]
}
