extension SupportedAPI.Matcher {
  var singleModelType: SupportedAPI.ModelType? {
    guard declarationFamilies.count == 1,
          let family = declarationFamilies.first
    else { return nil }
    return SupportedAPI.ModelType(declarationFamily: family)
  }
}
