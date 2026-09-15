extension BazelQueryResult {
  init(from decoder: any Decoder) throws {
    let fields = try decoder.container(keyedBy: Field.self)
    let resultsKey = Field(stringValue: "results")
    let configurationsKey = Field(stringValue: "configurations")
    if !fields.contains(resultsKey),
       fields.allKeys
       .contains(where: { $0.stringValue != configurationsKey.stringValue })
    {
      throw DecodingError.keyNotFound(resultsKey, .init(
        codingPath: decoder.codingPath,
        debugDescription: "The object must contain a cquery result."
      ))
    }
    results = try fields.decodeIfPresent(
      [ConfiguredTarget].self,
      forKey: resultsKey
    ) ?? []
    configurations = try fields.decodeIfPresent(
      [Configuration].self,
      forKey: configurationsKey
    )
  }

  private struct Field: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
      self.stringValue = stringValue
    }

    init?(intValue: Int) {
      nil
    }
  }
}
