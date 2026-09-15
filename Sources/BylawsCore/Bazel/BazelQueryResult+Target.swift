extension BazelQueryResult {
  struct ConfiguredTarget: Decodable {
    let target: Target
    let configurationId: Int?
  }

  struct Target: Decodable {
    let type: Kind
    let rule: Rule?
    let sourceFile: File?
    let generatedFile: File?
    let packageGroup: PackageGroup?

    enum Kind: String, Decodable {
      case rule = "RULE"
      case sourceFile = "SOURCE_FILE"
      case generatedFile = "GENERATED_FILE"
      case packageGroup = "PACKAGE_GROUP"

      init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let kind = Self(rawValue: value) else {
          throw QueryError(
            "The export contains unsupported target type '\(value)'."
          )
        }
        self = kind
      }
    }
  }

  struct Rule: Decodable {
    let name: String
    let ruleClass: String
    let location: String?
    let attribute: [Attribute]?
    let ruleInput: [String]?
    let configuredRuleInput: [Input]?
  }

  struct File: Decodable {
    let name: String
    let location: String?
    let generatingRule: String?
  }

  struct Attribute: Decodable {
    let name: String
    let stringListValue: [String]?
  }

  struct Input: Decodable {
    let label: String
    let configurationId: Int?
    let configurationChecksum: String?
  }

  struct PackageGroup: Decodable {
    let name: String
    let includedPackageGroup: [String]?
  }
}
