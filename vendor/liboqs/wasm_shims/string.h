/* Minimal <string.h> shim for wasm32-freestanding.
 *
 * The vendored liboqs ML-DSA + XKCP Keccak sources call memcpy, memset, and
 * memcmp. Zig's compiler-rt provides the first two as LLVM intrinsics on
 * freestanding-wasm; memcmp is also available via the same path.
 *
 * Declared here (not defined) so the C sources can link against whatever
 * implementation the surrounding toolchain supplies.
 */
#ifndef DREAMBALL_WASM_SHIM_STRING_H
#define DREAMBALL_WASM_SHIM_STRING_H

#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
int   memcmp(const void *s1, const void *s2, size_t n);

#endif
