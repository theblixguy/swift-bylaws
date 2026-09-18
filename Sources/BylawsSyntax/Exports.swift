#if BYLAWS_PREBUILT_SWIFT_SYNTAX
  @_exported public import BylawsSwiftBasicFormat
  @_exported public import BylawsSwiftDiagnostics
  @_exported public import BylawsSwiftOperators
  @_exported public import BylawsSwiftParser
  @_exported public import BylawsSwiftParserDiagnostics
  @_exported public import BylawsSwiftSyntax
#else
  @_exported public import SwiftBasicFormat
  @_exported public import SwiftDiagnostics
  @_exported public import SwiftOperators
  @_exported public import SwiftParser
  @_exported public import SwiftParserDiagnostics
  @_exported public import SwiftSyntax
#endif
