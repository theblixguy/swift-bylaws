extension SupportedAPI {
  static let manifestRuntimeMembers: [RuntimeMemberAPI] = {
    let table = ManifestMemberTable()
    return table.manifestListMembers
      + table.packageManifestMembers
      + table.packageElementMembers
      + table.targetMembers
      + table.pluginMembers
      + table.conditionMembers
      + table.versionMembers
      + table.unresolvedValueMembers
  }()
}
