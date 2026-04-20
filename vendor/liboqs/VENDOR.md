# Vendored liboqs subset — ML-DSA-87 only

## Pin

- Upstream: https://github.com/open-quantum-safe/liboqs
- Version: `0.13.0`
- Source of truth for this copy: `oqs-sys 0.11.0+liboqs-0.13.0` crate (cargo registry)
  — identical to the upstream release tarball, confirmed byte-for-byte.
- Copied on: 2026-04-20

## Scope

Only the files required to compile and call `pqcrystals_ml_dsa_87_ref_keypair` /
`_signature` / `_verify` are vendored. Everything else — KEMs, other sig schemes,
AVX2 backends, OpenSSL glue, the x4 parallel SHAKE variant — is intentionally
omitted.

## What's here

- `include/oqs/` — upstream public headers, copied verbatim except `oqs.h` and
  `oqsconfig.h`:
  - `common.h`, `rand.h`, `sha3.h`, `sha3_ops.h` (verbatim)
  - `oqs.h` — minimal override; upstream pulls in kem/sig/aes/etc. which are
    irrelevant here. Our version includes only the four headers listed above.
  - `oqsconfig.h` — hand-authored; only `OQS_ENABLE_SIG_ml_dsa_87` and the
    version string. Upstream's is CMake-generated and surfaces dozens of flags.
- `src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/` — the reference
  ML-DSA-87 implementation (8 `.c` files + their headers), verbatim from upstream.
- `src/common/pqclean_shims/randombytes.h`, `fips202.h` — PQClean compatibility
  shims the ref impl uses via `#include "randombytes.h"` / `#include "fips202.h"`.
- `src/common/sha3/sha3.c`, `xkcp_sha3.c`, `xkcp_dispatch.h` — SHAKE frontend and
  the XKCP backend that fills `sha3_default_callbacks`.
- `src/common/sha3/xkcp_low/KeccakP-1600/plain-64bits/*` — the portable 64-bit
  Keccak permutation. The AVX2 variant is not vendored; we never reach the
  runtime dispatch branch that would want it.
- `src/dreamball_stubs.c` — our own. Provides `OQS_randombytes` (libc-backed),
  `OQS_MEM_aligned_alloc` / `OQS_MEM_aligned_free` (`posix_memalign` + `free`).
  Upstream's `rand.c` and `common.c` are *not* vendored — their dependencies
  on `fopen("/dev/urandom")`, OpenSSL, and CPU-feature detection are not
  wanted here, and stubbing the handful of symbols we actually use is tiny.

## Refresh procedure

When bumping liboqs:

1. Download the upstream tarball for the new version.
2. Replace every file listed above with its upstream counterpart, *except*
   `include/oqs/oqs.h`, `include/oqs/oqsconfig.h`, and `src/dreamball_stubs.c`
   (ours).
3. Diff `include/oqs/common.h` / `rand.h` / `sha3.h` / `sha3_ops.h` between
   versions — if upstream added new `OQS_MEM_*` / `OQS_CPU_*` symbols that our
   stubs don't provide, add them to `dreamball_stubs.c`.
4. Re-run `zig build test` — the round-trip keypair/sign/verify test is the
   acceptance gate.
5. Update the "Copied on" date above.

## License

liboqs is MIT; the LICENSE file accompanying this note is the upstream license
text preserved verbatim. Each vendored file carries its own SPDX header.
