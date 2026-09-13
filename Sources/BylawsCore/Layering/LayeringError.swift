public import Foundation

/// An error in a layering declaration.
///
/// Later versions may add cases.
@nonexhaustive
public enum LayeringError: Error, Sendable, Hashable {
  /// More than one layer has the same name.
  case duplicateLayer(name: String)

  /// A `mayImport`, `mustImport` or `mustNotImport` name matches no
  /// declared layer.
  case unknownLayer(name: String, allowedBy: String)

  /// More than one layer declares the same module.
  case duplicateModule(name: String, layers: [String])

  /// A file matches the globs of more than one layer.
  case overlappingLayers(file: String, layers: [String])

  /// One layer may import another layer and must not import it.
  case contradictoryImport(layer: String, target: String)

  /// The declared import edges form a cycle.
  ///
  /// Swift modules cannot satisfy a cyclic layering. The path repeats its
  /// first layer at the end.
  case circularLayers(path: [String])
}

extension LayeringError: CustomStringConvertible {
  /// A message that names the problem and the fix.
  public var description: String {
    switch self {
    case let .duplicateLayer(name):
      "More than one layer is named '\(name)'. Give every layer a unique name."
    case let .unknownLayer(name, allowedBy):
      "Layer '\(allowedBy)' refers to '\(name)', but no layer has that "
        + "name. Declare the layer or fix the name."
    case let .duplicateModule(name, layers):
      "Layers \(layers.joinedWithAnd) each declare the module '\(name)'. "
        + "Declare each module in one layer."
    case let .overlappingLayers(file, layers):
      "The file '\(file)' matches the globs of layers \(layers.joinedWithAnd). "
        + "Make each glob match a different set of files."
    case let .contradictoryImport(layer, target):
      "Layer '\(layer)' may import '\(target)' and must not import it. "
        + "Remove one of the two."
    case let .circularLayers(path):
      "The declared imports form a cycle: "
        + "\(path.joined(separator: " imports ")). Break the cycle between "
        + "the layers."
    }
  }
}

extension [String] {
  fileprivate var joinedWithAnd: String {
    guard let last, count > 1 else { return joined() }
    return dropLast().joined(separator: ", ") + " and " + last
  }
}

extension LayeringError: LocalizedError {
  /// The same message as ``description``.
  public var errorDescription: String? { description }
}
