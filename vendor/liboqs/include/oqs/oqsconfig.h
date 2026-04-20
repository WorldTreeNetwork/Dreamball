/* Hand-authored oqsconfig.h for the Dreamball-vendored subset of liboqs 0.13.0.
 *
 * Upstream generates this file from oqsconfig.h.cmake at CMake configure time
 * with dozens of algorithm flags. We only need one algorithm — ML-DSA-87 — and
 * one backend (XKCP plain-64 SHAKE), so the whole file fits on a postcard.
 *
 * Deliberately undefined (leave commented so intent is explicit):
 *   OQS_DIST_X86_64_BUILD       — we do not emit AVX2 + plain64 dual builds
 *   OQS_ENABLE_SHA3_xkcp_low_avx2 — ditto; plain64 is the only backend
 *   OQS_USE_OPENSSL             — no OpenSSL linkage
 *   OQS_USE_PTHREADS            — the SHAKE dispatch falls back to a NULL check
 *   OQS_EMBEDDED_BUILD          — would disable randombytes_system
 */

#ifndef OQSCONFIG_H
#define OQSCONFIG_H

#define OQS_VERSION_TEXT "0.13.0-dreamball-mldsa-only"
#define OQS_COMPILE_BUILD_TARGET "custom-zig"

/* The one algorithm this build supports. */
#define OQS_ENABLE_SIG_ml_dsa_87 1

#endif /* OQSCONFIG_H */
