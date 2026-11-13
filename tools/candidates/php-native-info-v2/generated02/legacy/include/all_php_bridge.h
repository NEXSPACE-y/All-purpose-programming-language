#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef _WIN32
#include <wchar.h>
#define ALL_ABI_EXPORT __declspec(dllexport)
#else
#define ALL_ABI_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* Tags are the pinned PHP IS_* scalar tags. Bytes may contain NUL. */
typedef struct all_php_value {
    uint32_t type;
    uint32_t flags;
    int64_t integer;
    double real;
    const unsigned char *bytes;
    size_t length;
} all_php_value;
ALL_ABI_EXPORT int all_php_load_extension(const wchar_t *absolute_path);
ALL_ABI_EXPORT int all_php_request_start(void);
ALL_ABI_EXPORT int all_php_request_end(void);
ALL_ABI_EXPORT int all_php_shutdown(void);
ALL_ABI_EXPORT int all_php_invoke(const char *scope, const char *name,
    const all_php_value *args, uint32_t count, int strict_types, all_php_value *result);
ALL_ABI_EXPORT int all_php_invoke_frameless(const char *name, const all_php_value *arg,
    int strict_types, all_php_value *result);
ALL_ABI_EXPORT const char *all_php_error_class(void);
ALL_ABI_EXPORT const char *all_php_error_message(void);
/* v2 additive sized getter; borrowed bytes copied before another operation. */
ALL_ABI_EXPORT const char *all_php_error_message_bytes(size_t *length);
ALL_ABI_EXPORT const char *all_php_output(size_t *length);
ALL_ABI_EXPORT const char *all_php_diagnostics(size_t *length);
ALL_ABI_EXPORT void all_php_clear_output(void);
ALL_ABI_EXPORT const char *all_php_ini_get(const char *name);
ALL_ABI_EXPORT int all_php_ini_set(const char *name, const char *value);
ALL_ABI_EXPORT int all_php_constant_get(const char *name, all_php_value *result);
ALL_ABI_EXPORT const char *all_php_class_parent(const char *name);
ALL_ABI_EXPORT int all_php_class_property(const char *name, const char *property,
    uint32_t *flags, uint32_t *type_mask, int *initialized);
ALL_ABI_EXPORT const char *all_php_stats_json(void);
ALL_ABI_EXPORT const wchar_t *all_php_core_path(void);
ALL_ABI_EXPORT int all_php_module_info(void);
ALL_ABI_EXPORT const char *all_php_memory_probe(void);
ALL_ABI_EXPORT int all_php_has_function(const char *name);
ALL_ABI_EXPORT const char *all_php_function_catalog_json(void);
ALL_ABI_EXPORT const char *all_php_diagnostics_json(void);
ALL_ABI_EXPORT uint32_t all_php_diagnostic_count(void);
ALL_ABI_EXPORT const char *all_php_diagnostic_get(uint32_t index,int *level,size_t *length);
#ifdef __cplusplus
}
#endif
