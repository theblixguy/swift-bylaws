import CIndexStore
import Foundation

// Foundation does not re-export `dlopen` on every platform.
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@safe
final class IndexStoreLibrary {
  private let handle: DynamicLibraryHandle

  let storeCreate: bylaws_store_create_t
  let storeDispose: bylaws_store_dispose_t
  let errorDescription: bylaws_error_get_description_t
  let errorDispose: bylaws_error_dispose_t
  let unitsApply: bylaws_store_units_apply_t
  let unitReaderCreate: bylaws_unit_reader_create_t
  let unitReaderDispose: bylaws_unit_reader_dispose_t
  let unitModuleName: bylaws_unit_reader_string_t
  let unitMainFile: bylaws_unit_reader_string_t
  let unitOutputFile: bylaws_unit_reader_string_t
  let dependenciesApply: bylaws_unit_reader_dependencies_apply_t
  let dependencyKind: bylaws_dependency_kind_t
  let dependencyName: bylaws_dependency_string_t
  let dependencyPath: bylaws_dependency_string_t
  let recordReaderCreate: bylaws_record_reader_create_t
  let recordReaderDispose: bylaws_record_reader_dispose_t
  let occurrencesApply: bylaws_record_reader_occurrences_apply_t
  let occurrenceSymbol: bylaws_occurrence_get_symbol_t
  let occurrenceRoles: bylaws_occurrence_get_roles_t
  let occurrenceLineColumn: bylaws_occurrence_get_line_col_t
  let relationsApply: bylaws_occurrence_relations_apply_t
  let symbolUSR: bylaws_symbol_string_t
  let symbolName: bylaws_symbol_string_t
  let symbolKind: bylaws_symbol_get_kind_t
  let relationSymbol: bylaws_relation_get_symbol_t
  let relationRoles: bylaws_relation_get_roles_t

  init(path: String) throws(IndexStoreError) {
    let handle = try DynamicLibraryHandle(path: path)

    unsafe storeCreate = try handle.entry(
      "indexstore_store_create", as: bylaws_store_create_t.self
    )
    unsafe storeDispose = try handle.entry(
      "indexstore_store_dispose", as: bylaws_store_dispose_t.self
    )
    unsafe errorDescription = try handle.entry(
      "indexstore_error_get_description",
      as: bylaws_error_get_description_t.self
    )
    unsafe errorDispose = try handle.entry(
      "indexstore_error_dispose", as: bylaws_error_dispose_t.self
    )
    unsafe unitsApply = try handle.entry(
      "indexstore_store_units_apply_f", as: bylaws_store_units_apply_t.self
    )
    unsafe unitReaderCreate = try handle.entry(
      "indexstore_unit_reader_create", as: bylaws_unit_reader_create_t.self
    )
    unsafe unitReaderDispose = try handle.entry(
      "indexstore_unit_reader_dispose", as: bylaws_unit_reader_dispose_t.self
    )
    unsafe unitModuleName = try handle.entry(
      "indexstore_unit_reader_get_module_name",
      as: bylaws_unit_reader_string_t.self
    )
    unsafe unitMainFile = try handle.entry(
      "indexstore_unit_reader_get_main_file",
      as: bylaws_unit_reader_string_t.self
    )
    unsafe unitOutputFile = try handle.entry(
      "indexstore_unit_reader_get_output_file",
      as: bylaws_unit_reader_string_t.self
    )
    unsafe dependenciesApply = try handle.entry(
      "indexstore_unit_reader_dependencies_apply_f",
      as: bylaws_unit_reader_dependencies_apply_t.self
    )
    unsafe dependencyKind = try handle.entry(
      "indexstore_unit_dependency_get_kind", as: bylaws_dependency_kind_t.self
    )
    unsafe dependencyName = try handle.entry(
      "indexstore_unit_dependency_get_name", as: bylaws_dependency_string_t.self
    )
    unsafe dependencyPath = try handle.entry(
      "indexstore_unit_dependency_get_filepath",
      as: bylaws_dependency_string_t.self
    )
    unsafe recordReaderCreate = try handle.entry(
      "indexstore_record_reader_create", as: bylaws_record_reader_create_t.self
    )
    unsafe recordReaderDispose = try handle.entry(
      "indexstore_record_reader_dispose",
      as: bylaws_record_reader_dispose_t.self
    )
    unsafe occurrencesApply = try handle.entry(
      "indexstore_record_reader_occurrences_apply_f",
      as: bylaws_record_reader_occurrences_apply_t.self
    )
    unsafe occurrenceSymbol = try handle.entry(
      "indexstore_occurrence_get_symbol",
      as: bylaws_occurrence_get_symbol_t.self
    )
    unsafe occurrenceRoles = try handle.entry(
      "indexstore_occurrence_get_roles", as: bylaws_occurrence_get_roles_t.self
    )
    unsafe occurrenceLineColumn = try handle.entry(
      "indexstore_occurrence_get_line_col",
      as: bylaws_occurrence_get_line_col_t.self
    )
    unsafe relationsApply = try handle.entry(
      "indexstore_occurrence_relations_apply_f",
      as: bylaws_occurrence_relations_apply_t.self
    )
    unsafe symbolUSR = try handle.entry(
      "indexstore_symbol_get_usr", as: bylaws_symbol_string_t.self
    )
    unsafe symbolName = try handle.entry(
      "indexstore_symbol_get_name", as: bylaws_symbol_string_t.self
    )
    unsafe symbolKind = try handle.entry(
      "indexstore_symbol_get_kind", as: bylaws_symbol_get_kind_t.self
    )
    unsafe relationSymbol = try handle.entry(
      "indexstore_symbol_relation_get_symbol",
      as: bylaws_relation_get_symbol_t.self
    )
    unsafe relationRoles = try handle.entry(
      "indexstore_symbol_relation_get_roles",
      as: bylaws_relation_get_roles_t.self
    )
    self.handle = handle
  }

  // The description pointer remains valid until the error is disposed.
  func take(_ error: indexstore_error_t?) -> String {
    guard let error = unsafe error else {
      return "no reason"
    }
    defer { unsafe errorDispose(error) }
    guard let text = unsafe errorDescription(error) else {
      return "no reason"
    }
    return unsafe String(cString: text)
  }
}

@safe
private struct DynamicLibraryHandle: ~Copyable {
  private let rawValue: UnsafeMutableRawPointer

  init(path: String) throws(IndexStoreError) {
    guard let rawValue = unsafe dlopen(path, RTLD_LAZY) else {
      // dlerror() reports the failure above and clears it when read.
      let reason = unsafe dlerror().map { unsafe String(cString: $0) }
      throw .unreadableLibrary(
        path: path,
        reason: reason ?? "no reason available"
      )
    }
    unsafe self.rawValue = rawValue
  }

  deinit {
    unsafe dlclose(rawValue)
  }

  func entry<Function>(
    _ name: String, as type: Function.Type
  ) throws(IndexStoreError) -> Function {
    guard let symbol = unsafe dlsym(rawValue, name) else {
      throw .unsupportedLibrary(symbol: name)
    }
    return unsafe unsafeBitCast(symbol, to: type)
  }
}

extension indexstore_string_ref_t {
  // The applier invalidates the reference when the callback returns.
  var text: String {
    guard let data = unsafe data, unsafe length > 0 else { return "" }
    let bytes = unsafe UnsafeRawPointer(data)
      .assumingMemoryBound(to: UInt8.self)
    let buffer = unsafe UnsafeBufferPointer(start: bytes, count: length)
    // `UTF8Span` avoids validating the bytes twice on supported platforms.
    if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *),
       let utf8 = try? UTF8Span(validating: unsafe buffer.span)
    {
      return String(copying: utf8)
    }
    return unsafe String(decoding: buffer, as: UTF8.self)
  }
}
