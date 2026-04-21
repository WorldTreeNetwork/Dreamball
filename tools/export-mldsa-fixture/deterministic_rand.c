/*
 * Deterministic OQS_randombytes for the export-mldsa-fixture tool only.
 *
 * Uses a seeded xorshift64* PRNG so that `zig build export-mldsa-fixture`
 * produces the same ml_dsa_87_golden.json on every run. This is a KAT
 * (Known Answer Test) fixture — we deliberately want a fixed seed so the
 * test vector is stable and can be committed.
 *
 * DO NOT use this stubs file in production builds. It intentionally
 * replaces OQS_randombytes with a seeded PRNG. The native build uses
 * vendor/liboqs/src/dreamball_stubs.c which calls arc4random/getentropy.
 *
 * Seed value: the ASCII bytes of "dreamball-mldsa87-kat-seed-2026"
 * (padded to 64 bits with the byte sum) = 0x9B6E6441_4B415453.
 * Any fixed constant works; we pick something memorable.
 */

#include <stddef.h>
#include <stdint.h>

/* xorshift64* — Vigna 2014. Period 2^64-1, passes BigCrush. */
static uint64_t rng_state = 0x9B6E64414B415453ULL;

static uint64_t xorshift64star(void) {
    rng_state ^= rng_state >> 12;
    rng_state ^= rng_state << 25;
    rng_state ^= rng_state >> 27;
    return rng_state * 0x2545F4914F6CDD1DULL;
}

void OQS_randombytes(uint8_t *buf, size_t n) {
    size_t i = 0;
    while (i + 8 <= n) {
        uint64_t v = xorshift64star();
        buf[i]   = (uint8_t)(v);
        buf[i+1] = (uint8_t)(v >> 8);
        buf[i+2] = (uint8_t)(v >> 16);
        buf[i+3] = (uint8_t)(v >> 24);
        buf[i+4] = (uint8_t)(v >> 32);
        buf[i+5] = (uint8_t)(v >> 40);
        buf[i+6] = (uint8_t)(v >> 48);
        buf[i+7] = (uint8_t)(v >> 56);
        i += 8;
    }
    if (i < n) {
        uint64_t v = xorshift64star();
        while (i < n) {
            buf[i] = (uint8_t)(v & 0xff);
            v >>= 8;
            i++;
        }
    }
}

/* OQS_MEM_aligned_alloc / _free — same as dreamball_stubs.c */
#include <stdlib.h>

void *OQS_MEM_aligned_alloc(size_t alignment, size_t size) {
    void *ptr = NULL;
#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
    if (posix_memalign(&ptr, alignment, size) != 0) return NULL;
    return ptr;
#else
    return aligned_alloc(alignment, size);
#endif
}

void OQS_MEM_aligned_free(void *ptr) {
    free(ptr);
}
