extension BazelQueryResult {
  struct Configuration: Decodable {
    let id: Int
    let checksum: String
    let isTool: Bool?
    let fragmentOptions: [OptionGroup]?
  }

  struct OptionGroup: Decodable {
    let name: String
    let options: [Option]?
  }

  struct Option: Decodable {
    let name: String
    let value: String
  }

  func configurationsByID() throws -> [Int: BazelGraph.Configuration] {
    var result = [Int: BazelGraph.Configuration](
      minimumCapacity: configurations?.count ?? 0
    )
    for configuration in configurations ?? [] {
      var groups = [String: [String: String]](
        minimumCapacity: configuration.fragmentOptions?.count ?? 0
      )
      for group in configuration.fragmentOptions ?? [] {
        var options = [String: String](
          minimumCapacity: group.options?.count ?? 0
        )
        for option in group.options ?? [] {
          guard options.updateValue(option.value, forKey: option.name) == nil
          else {
            throw QueryError(
              "The export repeats option '\(option.name)' in '\(group.name)'."
            )
          }
        }
        guard groups.updateValue(options, forKey: group.name) == nil else {
          throw QueryError("The export repeats option group '\(group.name)'.")
        }
      }
      let value = BazelGraph.Configuration(
        checksum: configuration.checksum,
        isTool: configuration.isTool ?? false,
        buildOptions: groups
      )
      guard configuration.id > 0, !configuration.checksum.isEmpty,
            result.updateValue(value, forKey: configuration.id) == nil
      else {
        throw QueryError(
          "The export repeats or omits a configuration identifier."
        )
      }
    }
    return result
  }
}
