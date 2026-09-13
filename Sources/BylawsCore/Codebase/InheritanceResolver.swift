import BylawsSemantics

enum InheritanceResolver {
  static func resolve(in rawFiles: [SourceFile]) -> [SourceFile] {
    var declaredNames: Set<String> = []
    var namesBySimpleName: [String: [String]] = [:]
    func declare(_ qualifiedName: String) {
      guard declaredNames.insert(qualifiedName).inserted else { return }
      namesBySimpleName[Self.simpleName(of: qualifiedName), default: []]
        .append(qualifiedName)
    }
    for file in rawFiles {
      file.classes.forEach { declare($0.qualifiedName) }
      file.actors.forEach { declare($0.qualifiedName) }
      file.structs.forEach { declare($0.qualifiedName) }
      file.enums.forEach { declare($0.qualifiedName) }
      file.protocols.forEach { declare($0.name) }
    }

    func declarations(named writtenName: String) -> [String] {
      let written = Self.writtenName(of: writtenName)
      if declaredNames.contains(written) { return [written] }
      let candidates = namesBySimpleName[Self.simpleName(of: written)] ?? []
      guard candidates.count > 1 else { return candidates }
      let topLevelCandidates = candidates.filter { !$0.contains(".") }
      return topLevelCandidates.count == 1 ? topLevelCandidates : candidates
    }

    var conformances: [String: [String]] = [:]
    for anExtension in rawFiles.flatMap(\.extensions)
      where !anExtension.inheritedTypes.isEmpty
    {
      for name in declarations(named: anExtension.extendedTypeName) {
        conformances[name, default: []] += anExtension.inheritedTypes
      }
    }

    var parents = conformances
    var aliased: [String: String] = [:]
    func record(_ name: String, _ inheritedTypes: [String]) {
      parents[name, default: []] += inheritedTypes
    }
    for file in rawFiles {
      file.classes.forEach { record($0.qualifiedName, $0.inheritedTypes) }
      file.actors.forEach { record($0.qualifiedName, $0.inheritedTypes) }
      file.structs.forEach { record($0.qualifiedName, $0.inheritedTypes) }
      file.enums.forEach { record($0.qualifiedName, $0.inheritedTypes) }
      file.protocols.forEach { record($0.name, $0.inheritedTypes) }
      for alias in file.typealiases {
        aliased[alias.name] = Self.writtenName(of: alias.aliasedTypeName)
      }
    }

    var inheritanceLevelsByType: [String: [[String]]] = [:]
    func inheritanceLevels(from directType: String) -> [[String]] {
      if let levels = inheritanceLevelsByType[directType] { return levels }
      var levels: [[String]] = []
      var seen: Set<String> = []
      var expanded: Set<String> = []
      var queue = [(type: directType, level: 0)]
      var queueIndex = 0
      while queueIndex < queue.count {
        let (raw, level) = queue[queueIndex]
        queueIndex += 1
        while levels.count <= level { levels.append([]) }
        if seen.insert(raw).inserted { levels[level].append(raw) }
        var key = Self.writtenName(of: raw)
        let simple = Self.simpleName(of: key)
        if simple != raw,
           seen.insert(simple).inserted { levels[level].append(simple) }
        while let target = aliased[key], !expanded.contains(key) {
          expanded.insert(key)
          key = target
          if seen.insert(key).inserted { levels[level].append(key) }
          let simple = Self.simpleName(of: key)
          if seen.insert(simple).inserted { levels[level].append(simple) }
        }
        guard expanded.insert(key).inserted else { continue }
        for name in declarations(named: key) {
          queue += (parents[name] ?? []).map { ($0, level + 1) }
        }
      }
      inheritanceLevelsByType[directType] = levels
      return levels
    }

    var inheritedByDirectTypes: [[String]: [String]] = [:]
    func allInherited(from direct: [String]) -> [String] {
      if let inherited = inheritedByDirectTypes[direct] { return inherited }
      let inheritanceLevels = direct.map(inheritanceLevels(from:))
      let levelCount = inheritanceLevels.map(\.count).max() ?? 0
      var breadthFirstTypes: [String] = []
      var seen: Set<String> = []
      for level in 0..<levelCount {
        for levels in inheritanceLevels where level < levels.count {
          for name in levels[level] where seen.insert(name).inserted {
            breadthFirstTypes.append(name)
          }
        }
      }
      inheritedByDirectTypes[direct] = breadthFirstTypes
      return breadthFirstTypes
    }

    return rawFiles.map { file in
      var file = file
      func resolved<Declaration: NominalTypeStorageMutating>(
        _ declaration: Declaration
      ) -> Declaration {
        declaration.resolvingInheritance(
          extensionInheritedTypes: conformances[declaration.qualifiedName]
            ?? [],
          allInheritedTypes: allInherited(from:)
        )
      }
      file.classes = file.classes.map(resolved)
      file.actors = file.actors.map(resolved)
      file.structs = file.structs.map(resolved)
      file.enums = file.enums.map(resolved)
      file.protocols = file.protocols.map { declaration in
        var declaration = declaration
        declaration
          .extensionInheritedTypes = conformances[declaration.name] ?? []
        declaration.allInheritedTypes = allInherited(
          from: declaration.inheritedTypes + declaration.extensionInheritedTypes
        )
        return declaration
      }
      file.extensions = file.extensions.map { declaration in
        var declaration = declaration
        declaration.allInheritedTypes = allInherited(
          from: declaration.inheritedTypes
        )
        return declaration
      }
      return file
    }
  }

  private static func writtenName(of typeName: String) -> String {
    String(typeName.withoutTypeAttributes.prefix { $0 != "<" })
  }

  private static func simpleName(of typeName: String) -> String {
    let written = writtenName(of: typeName)
    return written.split(separator: ".").last.map(String.init) ?? written
  }
}
