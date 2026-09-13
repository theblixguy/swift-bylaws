package import BylawsSemantics

extension Rule.Findings {
  package init(
    layering violations: Violations<some Located>,
    missingImports: [Offender],
    emptyLayers: [String],
    reportedAt location: DeclarationLocation
  ) {
    let erased = violations.erased()
    self.init(
      violations: Violations(
        rule: erased.rule,
        offenders: erased.offenders + missingImports,
        checkedCount: erased.checkedCount
      ),
      warnings: Rule.Warning.emptyLayers(emptyLayers, reportedAt: location)
    )
  }
}

extension Rule.Warning {
  package static func emptyLayers(
    _ layers: [String],
    reportedAt location: DeclarationLocation
  ) -> [Rule.Warning] {
    layers.map { layer in
      Rule.Warning(
        message: "layer '\(layer)' matched no files",
        location: location
      )
    }
  }
}

extension LayeringCheck {
  package static func emptyLayerIssue(_ layer: String) -> String {
    "Layer '\(layer)' matched no files. Check the layer's globs."
  }
}
