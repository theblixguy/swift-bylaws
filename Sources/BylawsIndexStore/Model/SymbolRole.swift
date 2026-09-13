import CIndexStore

/// What a symbol does at one place in the source.
///
/// The compiler can record several roles at once. A dynamically dispatched
/// call carries both ``call`` and ``dynamic``.
public struct SymbolRole: OptionSet, Sendable, Hashable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  /// The source declares the symbol here.
  public static let declaration = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_DECLARATION
  )

  /// The source defines the symbol here, body included.
  public static let definition = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_DEFINITION
  )

  /// The source uses the symbol here.
  public static let reference = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REFERENCE
  )

  /// The source reads the value here.
  public static let read = SymbolRole(rawValue: INDEXSTORE_SYMBOL_ROLE_READ)

  /// The source writes the value here.
  public static let write = SymbolRole(rawValue: INDEXSTORE_SYMBOL_ROLE_WRITE)

  /// The source calls the symbol here.
  public static let call = SymbolRole(rawValue: INDEXSTORE_SYMBOL_ROLE_CALL)

  /// The compiler recorded the call against a dynamically dispatched
  /// requirement.
  public static let dynamic = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_DYNAMIC
  )

  /// The compiler synthesised the symbol without a source declaration.
  public static let implicit = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_IMPLICIT
  )

  /// The related symbol declares this one as a member.
  public static let childOf = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_CHILDOF
  )

  /// The related symbol inherits from this one, or conforms to it.
  public static let baseOf = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_BASEOF
  )

  /// The related symbol overrides this one.
  public static let overrideOf = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_OVERRIDEOF
  )

  /// The related symbol receives this call.
  public static let receivedBy = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_RECEIVEDBY
  )

  /// The related symbol makes this call.
  public static let calledBy = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_CALLEDBY
  )

  /// The related symbol extends this one.
  public static let extendedBy = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_EXTENDEDBY
  )

  /// The related symbol is an accessor of this one.
  public static let accessorOf = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_ACCESSOROF
  )

  /// The related symbol encloses this one.
  public static let containedBy = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_CONTAINEDBY
  )

  /// The related symbol is a specialisation of this one.
  public static let specializationOf = SymbolRole(
    rawValue: INDEXSTORE_SYMBOL_ROLE_REL_SPECIALIZATIONOF
  )
}
