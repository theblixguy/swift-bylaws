extension RuntimeFunctionDefinition {
  var runtimeType: SupportedAPI.RuntimeFunctionType {
    SupportedAPI.RuntimeFunctionType(
      name: name,
      parameters: parameters.map {
        SupportedAPI.RuntimeParameter(
          label: $0.externalName,
          type: $0.type
        )
      },
      result: returnType,
      isAsync: isAsync,
      isThrowing: isThrowing
    )
  }
}
