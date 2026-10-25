/// A model that can provide its original parsed source.
///
/// Models returned by ``FileCollector`` retain their original source.
/// Declaration models built with public initialisers have no captured source.
///
/// A declaration model's `Codable` conformance encodes its values and location
/// but omits its captured source. A decoded model can compare equal to the
/// original while its source projections throw ``SourceError/unavailable``.
///
/// ``SourceSlice`` retains its captured source when encoded and decoded.
public protocol SourceProviding: Sendable {
  /// The model's original source.
  ///
  /// - Throws: ``SourceError/unavailable`` when the model has no captured source.
  var source: SourceSlice { get throws }
}
