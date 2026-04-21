/* Minimal <stdlib.h> shim for wasm32-freestanding.
 *
 * liboqs's common.h references `exit` and `EXIT_FAILURE` from preprocessor
 * macros that the ML-DSA verify path never expands (they live in
 * SIZE_T_TO_INT_OR_EXIT-style guards that are unused in the reference
 * dilithium code). We still need the header to exist so `#include
 * <stdlib.h>` resolves; declaring `exit` keeps the one-off use sites
 * compilable.
 *
 * The verify-only path never calls malloc/free — OQS_MEM_aligned_alloc is
 * our static-arena replacement (see dreamball_stubs_wasm.c).
 */
#ifndef DREAMBALL_WASM_SHIM_STDLIB_H
#define DREAMBALL_WASM_SHIM_STDLIB_H

#include <stddef.h>

#define EXIT_FAILURE 1
#define EXIT_SUCCESS 0

void  exit(int status) __attribute__((noreturn));
void  abort(void) __attribute__((noreturn));
void *malloc(size_t size);
void  free(void *ptr);
void *calloc(size_t nmemb, size_t size);
int   posix_memalign(void **memptr, size_t alignment, size_t size);

#endif
