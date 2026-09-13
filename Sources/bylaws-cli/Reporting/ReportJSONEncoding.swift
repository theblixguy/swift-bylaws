import Foundation

func renderReportJSON(_ value: some Encodable) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [
    .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
  ]
  let data = try encoder.encode(value)
  return String(decoding: data, as: UTF8.self)
}
