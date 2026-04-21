/* Minimal <stdio.h> shim for wasm32-freestanding.
 *
 * liboqs's common.h includes <stdio.h> so its error macros
 * (`OQS_NULL_CHECK_OR_EXIT`, `OQS_OPENSSL_RETURN_CHECK_OR_EXIT`) can
 * reference fprintf + stderr. None of those macros are expanded on the
 * ML-DSA-87 verify path, so we only need the header to exist.
 *
 * We do declare FILE + stderr + fprintf as opaque externs so accidental
 * expansion fails at link time, not compile time.
 */
#ifndef DREAMBALL_WASM_SHIM_STDIO_H
#define DREAMBALL_WASM_SHIM_STDIO_H

#include <stddef.h>

typedef struct __DREAMBALL_FILE FILE;

extern FILE *stderr;
extern FILE *stdout;

int fprintf(FILE *stream, const char *format, ...);
int printf(const char *format, ...);

#endif
