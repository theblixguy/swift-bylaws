import BylawsPaths

package struct LayeringPlan: Sendable {
  package let layers: [Layer]
  package let layerForModule: [String: String]

  package struct Edge: Hashable, Sendable {
    package let source: String
    package let target: String

    package init(source: String, target: String) {
      self.source = source
      self.target = target
    }
  }

  package init(
    _ layering: Layering,
    validatesModuleOwnership: Bool
  ) throws(LayeringError) {
    layers = layering.layers

    var names: Set<String> = []
    for layer in layers where !names.insert(layer.name).inserted {
      throw LayeringError.duplicateLayer(name: layer.name)
    }
    for layer in layers {
      let referenced = (layer.allowedImports ?? []) + layer.requiredImports
        + layer.forbiddenImports
      for name in referenced where !names.contains(name) {
        throw LayeringError.unknownLayer(name: name, allowedBy: layer.name)
      }
      let named = (layer.importPolicy.allowedLayers ?? [])
        + layer.requiredImports
      for name in layer.forbiddenImports where named.contains(name) {
        throw LayeringError.contradictoryImport(
          layer: layer.name,
          target: name
        )
      }
    }
    if let cycle = layering.declaredCycle() {
      throw LayeringError.circularLayers(path: cycle)
    }

    var modules: [String: String] = [:]
    if validatesModuleOwnership {
      for layer in layers {
        for module in layer.modules {
          if let owner = modules[module], owner != layer.name {
            throw LayeringError.duplicateModule(
              name: module,
              layers: [owner, layer.name]
            )
          }
          modules[module] = layer.name
        }
      }
    }
    layerForModule = modules
  }

  package func layer(
    containing filePath: String,
    relativeTo rootPath: String
  ) throws(LayeringError) -> Layer? {
    let relativePath = LexicalFilePath(filePath)
      .relative(to: LexicalFilePath(rootPath))?.string ?? filePath
    let matching = layers.filter { layer in
      layer.files.contains { $0.matches(relativePath) }
    }
    guard let layer = matching.first else { return nil }
    guard matching.count == 1 else {
      throw LayeringError.overlappingLayers(
        file: relativePath,
        layers: matching.map(\.name)
      )
    }
    return layer
  }

  package func allowsDependency(
    from layer: Layer,
    to target: String
  ) -> Bool {
    target == layer.name
      || layer.requiredImports.contains(target)
      || !layer.forbiddenImports.contains(target)
      && layer.importPolicy.allows(target)
  }

  package func emptyLayers(given layersWithFiles: Set<String>) -> [String] {
    layers.map(\.name).filter { !layersWithFiles.contains($0) }
  }

  package func missingImports(
    given usedEdges: Set<Edge>
  ) -> [LayeringCheck.MissingImport] {
    layers.flatMap { layer in
      layer.requiredImports
        .filter { !usedEdges.contains(Edge(source: layer.name, target: $0)) }
        .map {
          LayeringCheck.MissingImport(layer: layer.name, requiredImport: $0)
        }
    }
  }
}
