/* Minimal <limits.h> shim for wasm32-freestanding.
 *
 * liboqs's common.h references INT_MAX inside a macro that the ML-DSA
 * verify path never expands. We only need the symbol to exist so the
 * preprocessor is happy.
 */
#ifndef DREAMBALL_WASM_SHIM_LIMITS_H
#define DREAMBALL_WASM_SHIM_LIMITS_H

#define INT_MAX 2147483647

#endif
