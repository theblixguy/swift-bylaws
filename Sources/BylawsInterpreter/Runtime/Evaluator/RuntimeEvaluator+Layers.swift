import BylawsCore

extension RuntimeEvaluator {
  func constructLayer(_ arguments: RuntimeArguments) throws(RuntimeError)
    -> RuntimeValue
  {
    var files: [Glob] = []
    var modules: [String]?
    var policy = Layer.ImportPolicy.only([])
    var required: [String] = []
    var forbidden: [String] = []
    for index in arguments.values.indices.dropFirst() {
      switch arguments.label(at: index) {
      case .files: files = try arguments.strings(at: index).map { Glob($0) }
      case .modules: modules = try arguments.strings(at: index)
      case .mayImport:
        if case .member(.constant(.any)) = try arguments
          .value(at: index) { policy = .any }
        else { policy = .only(try arguments.strings(at: index)) }
      case .mustImport: required = try arguments.strings(at: index)
      case .mustNotImport: forbidden = try arguments.strings(at: index)
      default: throw RuntimeError(
          message: "Layer cannot use this argument",
          location: arguments.location
        )
      }
    }
    return .layer(Layer(
      try arguments.string(at: 0),
      files: files,
      modules: modules,
      mayImport: policy,
      mustImport: required,
      mustNotImport: forbidden
    ))
  }
}
