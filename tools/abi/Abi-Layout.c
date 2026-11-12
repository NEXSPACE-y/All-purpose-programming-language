/* Compile against the pinned PHP devel headers, never link php8ts.lib.
 * This executable reports compile-time layout constants; it does not load PHP.
 */
#include <stddef.h>
#include <stdio.h>
#include "php.h"
#include "zend_modules.h"
#include "zend_extensions.h"

#define SIZE(T) printf("\"sizeof_%s\":%zu,", #T, sizeof(T))
#define OFF(T, F) printf("\"offsetof_%s_%s\":%zu,", #T, #F, offsetof(T, F))

int main(void) {
    printf("{");
    printf("\"method\":\"compiled_header_constants_no_php_link\",");
    printf("\"php_version\":\"%s\",", PHP_VERSION);
    printf("\"module_api\":%d,", ZEND_MODULE_API_NO);
    printf("\"module_build_id\":\"%s\",", ZEND_MODULE_BUILD_ID);
    printf("\"zend_extension_api\":%d,", ZEND_EXTENSION_API_NO);
    printf("\"zts\":%d,\"zend_debug\":%d,", USING_ZTS, ZEND_DEBUG);
    SIZE(void*); SIZE(zend_long); SIZE(zend_value); SIZE(zval);
    SIZE(zend_refcounted_h); SIZE(zend_string); SIZE(zend_array);
    SIZE(Bucket); SIZE(zend_object); SIZE(zend_reference);
    SIZE(zend_execute_data); SIZE(zend_function_entry);
    SIZE(zend_module_entry); SIZE(zend_extension);
    OFF(zval, value); OFF(zval, u1); OFF(zval, u2);
    OFF(zend_string, gc); OFF(zend_string, h); OFF(zend_string, len); OFF(zend_string, val);
    OFF(zend_object, gc); OFF(zend_object, handle); OFF(zend_object, ce);
    OFF(zend_object, handlers); OFF(zend_object, properties); OFF(zend_object, properties_table);
    OFF(zend_execute_data, func); OFF(zend_execute_data, This); OFF(zend_execute_data, prev_execute_data);
    OFF(zend_module_entry, size); OFF(zend_module_entry, zend_api);
    OFF(zend_module_entry, zend_debug); OFF(zend_module_entry, zts);
    OFF(zend_module_entry, name); OFF(zend_module_entry, functions);
    OFF(zend_module_entry, module_startup_func); OFF(zend_module_entry, request_startup_func);
    OFF(zend_module_entry, version); OFF(zend_module_entry, globals_size);
    OFF(zend_module_entry, globals_id_ptr); OFF(zend_module_entry, build_id);
    printf("\"compiler_msc_ver\":%d,\"compiler_msc_full_ver\":%d}", _MSC_VER, _MSC_FULL_VER);
    return 0;
}
