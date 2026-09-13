#ifndef BYLAWS_C_INDEX_STORE_H
#define BYLAWS_C_INDEX_STORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// These declarations mirror IndexStore's C ABI without linking Bylaws to a
// toolchain.

typedef struct {
  const char *data;
  size_t length;
} indexstore_string_ref_t;

typedef void *indexstore_error_t;
typedef void *indexstore_t;
typedef void *indexstore_symbol_t;
typedef void *indexstore_symbol_relation_t;
typedef void *indexstore_occurrence_t;
typedef void *indexstore_record_reader_t;
typedef void *indexstore_unit_reader_t;
typedef void *indexstore_unit_dependency_t;

typedef enum {
  INDEXSTORE_SYMBOL_KIND_UNKNOWN = 0,
  INDEXSTORE_SYMBOL_KIND_MODULE = 1,
  INDEXSTORE_SYMBOL_KIND_NAMESPACE = 2,
  INDEXSTORE_SYMBOL_KIND_NAMESPACEALIAS = 3,
  INDEXSTORE_SYMBOL_KIND_MACRO = 4,
  INDEXSTORE_SYMBOL_KIND_ENUM = 5,
  INDEXSTORE_SYMBOL_KIND_STRUCT = 6,
  INDEXSTORE_SYMBOL_KIND_CLASS = 7,
  INDEXSTORE_SYMBOL_KIND_PROTOCOL = 8,
  INDEXSTORE_SYMBOL_KIND_EXTENSION = 9,
  INDEXSTORE_SYMBOL_KIND_UNION = 10,
  INDEXSTORE_SYMBOL_KIND_TYPEALIAS = 11,
  INDEXSTORE_SYMBOL_KIND_FUNCTION = 12,
  INDEXSTORE_SYMBOL_KIND_VARIABLE = 13,
  INDEXSTORE_SYMBOL_KIND_FIELD = 14,
  INDEXSTORE_SYMBOL_KIND_ENUMCONSTANT = 15,
  INDEXSTORE_SYMBOL_KIND_INSTANCEMETHOD = 16,
  INDEXSTORE_SYMBOL_KIND_CLASSMETHOD = 17,
  INDEXSTORE_SYMBOL_KIND_STATICMETHOD = 18,
  INDEXSTORE_SYMBOL_KIND_INSTANCEPROPERTY = 19,
  INDEXSTORE_SYMBOL_KIND_CLASSPROPERTY = 20,
  INDEXSTORE_SYMBOL_KIND_STATICPROPERTY = 21,
  INDEXSTORE_SYMBOL_KIND_CONSTRUCTOR = 22,
  INDEXSTORE_SYMBOL_KIND_DESTRUCTOR = 23,
  INDEXSTORE_SYMBOL_KIND_CONVERSIONFUNCTION = 24,
  INDEXSTORE_SYMBOL_KIND_PARAMETER = 25,
  INDEXSTORE_SYMBOL_KIND_USING = 26,
  INDEXSTORE_SYMBOL_KIND_CONCEPT = 27,
  INDEXSTORE_SYMBOL_KIND_COMMENTTAG = 1000,
} indexstore_symbol_kind_t;

typedef uint64_t indexstore_symbol_role_t;

#define INDEXSTORE_SYMBOL_ROLE_DECLARATION (1ull << 0)
#define INDEXSTORE_SYMBOL_ROLE_DEFINITION (1ull << 1)
#define INDEXSTORE_SYMBOL_ROLE_REFERENCE (1ull << 2)
#define INDEXSTORE_SYMBOL_ROLE_READ (1ull << 3)
#define INDEXSTORE_SYMBOL_ROLE_WRITE (1ull << 4)
#define INDEXSTORE_SYMBOL_ROLE_CALL (1ull << 5)
#define INDEXSTORE_SYMBOL_ROLE_DYNAMIC (1ull << 6)
#define INDEXSTORE_SYMBOL_ROLE_ADDRESSOF (1ull << 7)
#define INDEXSTORE_SYMBOL_ROLE_IMPLICIT (1ull << 8)
#define INDEXSTORE_SYMBOL_ROLE_REL_CHILDOF (1ull << 9)
#define INDEXSTORE_SYMBOL_ROLE_REL_BASEOF (1ull << 10)
#define INDEXSTORE_SYMBOL_ROLE_REL_OVERRIDEOF (1ull << 11)
#define INDEXSTORE_SYMBOL_ROLE_REL_RECEIVEDBY (1ull << 12)
#define INDEXSTORE_SYMBOL_ROLE_REL_CALLEDBY (1ull << 13)
#define INDEXSTORE_SYMBOL_ROLE_REL_EXTENDEDBY (1ull << 14)
#define INDEXSTORE_SYMBOL_ROLE_REL_ACCESSOROF (1ull << 15)
#define INDEXSTORE_SYMBOL_ROLE_REL_CONTAINEDBY (1ull << 16)
#define INDEXSTORE_SYMBOL_ROLE_REL_IBTYPEOF (1ull << 17)
#define INDEXSTORE_SYMBOL_ROLE_REL_SPECIALIZATIONOF (1ull << 18)
#define INDEXSTORE_SYMBOL_ROLE_UNDEFINITION (1ull << 19)
#define INDEXSTORE_SYMBOL_ROLE_NAMEREFERENCE (1ull << 20)

typedef enum {
  INDEXSTORE_UNIT_DEPENDENCY_UNIT = 1,
  INDEXSTORE_UNIT_DEPENDENCY_RECORD = 2,
  INDEXSTORE_UNIT_DEPENDENCY_FILE = 3,
} indexstore_unit_dependency_kind_t;

typedef indexstore_t (*bylaws_store_create_t)(const char *store_path,
                                              indexstore_error_t *error);
typedef void (*bylaws_store_dispose_t)(indexstore_t);
typedef const char *(*bylaws_error_get_description_t)(indexstore_error_t);
typedef void (*bylaws_error_dispose_t)(indexstore_error_t);

typedef bool (*bylaws_unit_applier_t)(void *context,
                                      indexstore_string_ref_t unit_name);
typedef bool (*bylaws_store_units_apply_t)(indexstore_t, unsigned sorted,
                                           void *context,
                                           bylaws_unit_applier_t applier);

typedef indexstore_unit_reader_t (*bylaws_unit_reader_create_t)(
    indexstore_t store, const char *unit_name, indexstore_error_t *error);
typedef void (*bylaws_unit_reader_dispose_t)(indexstore_unit_reader_t);
typedef indexstore_string_ref_t (*bylaws_unit_reader_string_t)(
    indexstore_unit_reader_t);

typedef bool (*bylaws_dependency_applier_t)(void *context,
                                            indexstore_unit_dependency_t);
typedef bool (*bylaws_unit_reader_dependencies_apply_t)(
    indexstore_unit_reader_t, void *context,
    bylaws_dependency_applier_t applier);
typedef indexstore_unit_dependency_kind_t (*bylaws_dependency_kind_t)(
    indexstore_unit_dependency_t);
typedef indexstore_string_ref_t (*bylaws_dependency_string_t)(
    indexstore_unit_dependency_t);

typedef indexstore_record_reader_t (*bylaws_record_reader_create_t)(
    indexstore_t store, const char *record_name, indexstore_error_t *error);
typedef void (*bylaws_record_reader_dispose_t)(indexstore_record_reader_t);

typedef bool (*bylaws_occurrence_applier_t)(void *context,
                                            indexstore_occurrence_t);
typedef bool (*bylaws_record_reader_occurrences_apply_t)(
    indexstore_record_reader_t, void *context,
    bylaws_occurrence_applier_t applier);

typedef indexstore_symbol_t (*bylaws_occurrence_get_symbol_t)(
    indexstore_occurrence_t);
typedef indexstore_symbol_role_t (*bylaws_occurrence_get_roles_t)(
    indexstore_occurrence_t);
typedef void (*bylaws_occurrence_get_line_col_t)(indexstore_occurrence_t,
                                                 unsigned *line,
                                                 unsigned *column);

typedef bool (*bylaws_relation_applier_t)(void *context,
                                          indexstore_symbol_relation_t);
typedef bool (*bylaws_occurrence_relations_apply_t)(
    indexstore_occurrence_t, void *context, bylaws_relation_applier_t applier);

typedef indexstore_string_ref_t (*bylaws_symbol_string_t)(indexstore_symbol_t);
typedef indexstore_symbol_kind_t (*bylaws_symbol_get_kind_t)(
    indexstore_symbol_t);
typedef indexstore_symbol_t (*bylaws_relation_get_symbol_t)(
    indexstore_symbol_relation_t);
typedef indexstore_symbol_role_t (*bylaws_relation_get_roles_t)(
    indexstore_symbol_relation_t);

#endif
