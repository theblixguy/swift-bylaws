package import BylawsSemantics

extension DeclarationLocation {
  package static func rulesFile(atRoot rootPath: String) -> Self {
    .start(of: rootPath.isEmpty ? "Bylaws.swift" : "\(rootPath)/Bylaws.swift")
  }
}
