/* Dreamball WASM-freestanding liboqs link stubs.
 *
 * Mirror of dreamball_stubs.c for wasm32-freestanding targets, where libc
 * is absent. Two things need stubbing:
 *
 *   1. OQS_randombytes — liboqs's one and only entropy entry point. The
 *      ML-DSA-87 VERIFY path never calls it (only keypair + sign do), so
 *      this stub just traps. If the linker pulls it in anyway as a dead
 *      reference from crypto_sign_keypair / crypto_sign, it will only
 *      trap if that dead code is ever executed — which, for a verify-only
 *      browser build, never happens.
 *
 *   2. OQS_MEM_aligned_alloc / OQS_MEM_aligned_free — xkcp_sha3.c calls
 *      these to allocate the 224-byte Keccak incremental state. The
 *      Dilithium ref impl uses a handful of short-lived SHAKE contexts
 *      during one verify call (SampleInBall, ExpandA, H for mu, ...),
 *      each of which init+release pairs deterministically. A fixed
 *      pool of 8 slots is ample; ML-DSA-87 never holds more than 2
 *      concurrent SHAKE contexts in practice.
 *
 * Keeping the arena static avoids dragging a full allocator (malloc,
 * free, sbrk, mmap) into the WASM binary, which is the entire point of
 * the verify-only spike. Zig's compiler-rt already provides memcpy +
 * memset — the only libc bits the Keccak backend uses.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* -- Entropy --------------------------------------------------------------- */

void OQS_randombytes(uint8_t *buf, size_t n);

void OQS_randombytes(uint8_t *buf, size_t n) {
    (void)buf;
    (void)n;
    /* Verify-only WASM never reaches this. Trap hard so any accidental
       sign/keypair call from a dead-code path is loud, not silent. */
    __builtin_trap();
}

/* -- Aligned allocation (static arena) ------------------------------------- */

#define OQS_WASM_SLOT_BYTES  256
#define OQS_WASM_SLOT_COUNT  8

static __attribute__((aligned(32))) uint8_t oqs_wasm_arena[OQS_WASM_SLOT_BYTES * OQS_WASM_SLOT_COUNT];
static uint8_t oqs_wasm_slot_used[OQS_WASM_SLOT_COUNT];

void *OQS_MEM_aligned_alloc(size_t alignment, size_t size);
void  OQS_MEM_aligned_free(void *ptr);

void *OQS_MEM_aligned_alloc(size_t alignment, size_t size) {
    (void)alignment; /* arena is 32-byte aligned; slots are aligned too */
    if (size > OQS_WASM_SLOT_BYTES) {
        /* Caller asked for more than a slot. Fail loudly. */
        return (void *)0;
    }
    for (int i = 0; i < OQS_WASM_SLOT_COUNT; i++) {
        if (!oqs_wasm_slot_used[i]) {
            oqs_wasm_slot_used[i] = 1;
            return &oqs_wasm_arena[i * OQS_WASM_SLOT_BYTES];
        }
    }
    return (void *)0;
}

void OQS_MEM_aligned_free(void *ptr) {
    if (!ptr) return;
    uintptr_t p = (uintptr_t)ptr;
    uintptr_t base = (uintptr_t)oqs_wasm_arena;
    if (p < base || p >= base + sizeof(oqs_wasm_arena)) return;
    size_t slot = (p - base) / OQS_WASM_SLOT_BYTES;
    oqs_wasm_slot_used[slot] = 0;
}

/* -- exit / fprintf / stderr stubs ----------------------------------------
 *
 * OQS common.h's OQS_EXIT_IF_NULLPTR macro expands to `fprintf(stderr,
 * ...); exit(EXIT_FAILURE);`. It only fires when OQS_MEM_aligned_alloc
 * returns NULL — i.e., our static arena exhausted. Trapping is the right
 * behaviour in the browser (hard-fail, surface via wasm-ld exception).
 *
 * Providing these as link-time symbols lets the macros compile cleanly
 * without having to patch vendored common.h.
 */

struct __DREAMBALL_FILE { int _unused; };
static struct __DREAMBALL_FILE __dreamball_stderr_sentinel;
FILE *stderr = &__dreamball_stderr_sentinel;

void exit(int status) {
    (void)status;
    __builtin_trap();
}

int fprintf(FILE *stream, const char *format, ...) {
    (void)stream;
    (void)format;
    return 0;
}
