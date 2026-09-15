import BylawsPaths
import BylawsSemantics

struct BazelQueryResult: Decodable {
  let results: [ConfiguredTarget]
  let configurations: [Configuration]?

  func graph(rootPath: String, exportPath: String) throws -> BazelGraph {
    let configurations = try configurationsByID()

    func configuration(for id: Int?) throws -> BazelGraph.Configuration? {
      guard let id, id != 0 else { return nil }
      guard let value = configurations[id] else {
        throw QueryError("The export omits configuration \(id).")
      }
      return value
    }

    var entries: [(target: BazelGraph.Target, inputs: [BazelGraph.Key])] = []
    entries.reserveCapacity(results.count)
    for result in results {
      let targetConfiguration = try configuration(for: result.configurationId)
      let target = result.target
      let name: String
      let sourceLocation: String?
      var inputs: [BazelGraph.Key] = []
      switch target.type {
      case .packageGroup:
        guard let group = target.packageGroup else {
          throw QueryError("A package group has no group data.")
        }
        name = group.name
        sourceLocation = nil
        inputs = (group.includedPackageGroup ?? []).map {
          BazelGraph.Key(label: $0, configuration: nil)
        }
      case .rule:
        guard let rule = target.rule else {
          throw QueryError("A rule target has no rule data.")
        }
        guard targetConfiguration != nil else {
          throw QueryError(
            "The export omits the configuration for '\(rule.name)'."
          )
        }
        guard rule.ruleInput?.isEmpty != false || rule.configuredRuleInput?
          .isEmpty == false
        else {
          throw QueryError(
            "The export omits configured dependencies for '\(rule.name)'."
          )
        }
        name = rule.name
        sourceLocation = rule.location
        inputs.reserveCapacity(rule.configuredRuleInput?.count ?? 0)
        for input in rule.configuredRuleInput ?? [] {
          let inputConfiguration = try configuration(for: input.configurationId)
          guard input.configurationChecksum == nil || input
            .configurationChecksum == inputConfiguration?.checksum
          else {
            throw QueryError(
              "The dependency '\(input.label)' has inconsistent configuration data."
            )
          }
          inputs.append(BazelGraph.Key(
            label: input.label,
            configuration: inputConfiguration?.checksum
          ))
        }
      case .sourceFile, .generatedFile:
        let file = if target.type == .sourceFile {
          target.sourceFile
        } else {
          target.generatedFile
        }
        guard let file
        else { throw QueryError("A file target has no file data.") }
        name = file.name
        sourceLocation = file.location
        if target.type == .generatedFile {
          guard let generator = file.generatingRule else {
            throw QueryError(
              "The export omits the generating rule for '\(name)'."
            )
          }
          inputs.append(BazelGraph.Key(
            label: generator,
            configuration: targetConfiguration?.checksum
          ))
        }
      }
      entries.append((
        BazelGraph.Target(
          label: name,
          configuration: targetConfiguration,
          ruleClass: target.rule?.ruleClass,
          tags: target.rule?.attribute?.first { $0.name == "tags" }?
            .stringListValue ?? [],
          location: location(
            sourceLocation,
            rootPath: rootPath,
            exportPath: exportPath
          )
        ),
        inputs
      ))
    }
    entries.sort {
      ($0.target.label, $0.target.configuration?.checksum ?? "") < (
        $1.target.label,
        $1.target.configuration?.checksum ?? ""
      )
    }
    let targets = entries.map(\.target)
    var indices = [BazelGraph.Key: Int](minimumCapacity: targets.count)
    for (index, target) in targets.enumerated() {
      guard indices.updateValue(index, forKey: target.key) == nil else {
        throw QueryError(
          "The export repeats configured target '\(target.label)'."
        )
      }
    }
    var edges: [DirectedEdge<Int>] = []
    for (index, entry) in entries.enumerated() {
      for input in entry.inputs {
        guard let destination = indices[input] else {
          throw QueryError(
            "The export omits dependency '\(input.label)' of '\(entry.target.label)'."
          )
        }
        edges.append(DirectedEdge(from: index, to: destination))
      }
    }
    return BazelGraph(targets: targets, indices: indices, edges: edges)
  }

  private func location(
    _ text: String?,
    rootPath: String,
    exportPath: String
  ) -> DeclarationLocation {
    guard let text,
          let columnSeparator = text.lastIndex(of: ":"),
          let column = Int(text[text.index(after: columnSeparator)...]),
          column > 0,
          let lineSeparator = text[..<columnSeparator].lastIndex(of: ":"),
          let line =
          Int(text[text.index(after: lineSeparator)..<columnSeparator]),
          line > 0
    else { return .start(of: exportPath) }
    let path = LexicalFilePath(
      String(text[..<lineSeparator]),
      relativeTo: LexicalFilePath(rootPath)
    )
    return DeclarationLocation(
      filePath: path.string,
      line: line,
      column: column
    )
  }

  struct QueryError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
      self.description = description
    }
  }
}
