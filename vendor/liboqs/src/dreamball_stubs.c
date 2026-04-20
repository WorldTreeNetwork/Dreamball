/* Dreamball-specific liboqs link stubs.
 *
 * Upstream liboqs carries rand.c and common.c, which pull in fopen, getentropy,
 * arc4random, CPU-feature detection via CPUID, and OpenSSL glue. Our vendored
 * subset doesn't need any of that — the ML-DSA-87 ref impl calls exactly two
 * entry points not defined by its own sources: OQS_randombytes (via the
 * pqclean_shims "randombytes" macro) and the two OQS_MEM_aligned_* helpers
 * (only xkcp_sha3.c uses them, for the Keccak incremental state ctx). We
 * provide those here and skip the rest.
 *
 * Why not vendor common.c? It would pull in pthread_once glue and the
 * full OQS_CPU_has_extension CPUID table, neither of which is reachable
 * when OQS_DIST_X86_64_BUILD is off (and we never turn it on here).
 *
 * Why not vendor rand.c? It prefers fopen("/dev/urandom") on Linux and
 * arc4random_buf on macOS — fine on native but it also ships the
 * OQS_randombytes_{switch,custom}_algorithm dispatch layer, which we
 * would never call. A single direct function is simpler.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
#include <unistd.h>
#endif

#if defined(__linux__)
#include <sys/random.h>
#endif

/* -- Entropy --------------------------------------------------------------- */

void OQS_randombytes(uint8_t *buf, size_t n);

void OQS_randombytes(uint8_t *buf, size_t n) {
#if defined(__APPLE__)
    /* arc4random_buf is declared in <stdlib.h> on Apple platforms. */
    arc4random_buf(buf, n);
#elif defined(__linux__)
    /* getentropy is limited to 256 bytes per call on Linux. */
    while (n > 0) {
        size_t chunk = n > 256 ? 256 : n;
        if (getentropy(buf, chunk) != 0) {
            /* Fatal: no entropy source, no safe recovery. */
            abort();
        }
        buf += chunk;
        n -= chunk;
    }
#elif defined(_WIN32)
    /* TODO: BCryptGenRandom when we ship a Windows build. We do not today. */
    (void)buf;
    (void)n;
    abort();
#else
    /* Freestanding targets (wasm32-freestanding) must link their own
       OQS_randombytes. This stub is only compiled into the native build. */
    (void)buf;
    (void)n;
    abort();
#endif
}

/* -- Aligned allocation ---------------------------------------------------- */

/* xkcp_sha3.c uses these to allocate the 224-byte Keccak incremental state.
 * posix_memalign requires alignment to be a power of two and a multiple of
 * sizeof(void *); KECCAK_CTX_ALIGNMENT is 32 which satisfies both. */

void *OQS_MEM_aligned_alloc(size_t alignment, size_t size) {
    void *ptr = NULL;
#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
    if (posix_memalign(&ptr, alignment, size) != 0) {
        return NULL;
    }
    return ptr;
#else
    return aligned_alloc(alignment, size);
#endif
}

void OQS_MEM_aligned_free(void *ptr) {
    free(ptr);
}
