/// A model that can provide its original parsed source.
///
/// Models returned by ``FileCollector`` retain their original source. Public
/// initialisers create models without captured source.
///
/// A model's `Codable` conformance encodes its values and location but omits
/// its captured source. A decoded model can compare equal to the original
/// while its source projections throw ``SourceError/unavailable``.
/// Bylaws' parse cache retains the captured source.
public protocol SourceProviding: Sendable {
  /// The model's original source.
  ///
  /// - Throws: ``SourceError/unavailable`` when the model has no captured source.
  var source: SourceSlice { get throws }
}
