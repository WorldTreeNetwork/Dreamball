# Known Gaps

The residual `TODO-CRYPTO` and deferred-work items in DreamBall, each
tied to an engineering plan or a tracking entry. Every gap must either
resolve to real code or to a deliberate Vision-tier decision — nothing
lingers here without a clear next step.

---

## Active gaps (post v2.1)

### 1. Browser-side ML-DSA-87 verification

**State — CLOSED 2026-04-22 by S1.1 completion. Remaining item below is polish only.**

`verifyJelly` in `jelly.wasm` verifies Ed25519 locally and ML-DSA-87
signatures against the envelope's `identity-pq` core field. The default
`zig build wasm` ships with PQ-verify enabled (`-Dpq-wasm=true` is the
default). A standalone `verifyMlDsa(sig, msg, pk)` export is fully tested
via a pinned KAT fixture (`fixtures/ml_dsa_87_golden.json`, generated
deterministically by `zig build export-mldsa-fixture`). All AC1–AC5 of
Story 1.1 are green; see `src/lib/wasm/verify.test.ts` for the primitive
+ budget assertions.

**Verify-only spike results.** Vendored liboqs (ML-DSA-87 ref impl +
XKCP SHAKE) compiled for wasm32-freestanding via four shim headers
(`<string.h>`, `<stdlib.h>`, `<stdio.h>`, `<limits.h>` in
`vendor/liboqs/wasm_shims/`) + a freestanding stubs file
(`dreamball_stubs_wasm.c`, static 8×256-byte arena for the Keccak
context alloc, traps for unreachable exit/fprintf/randombytes).
wasm-ld's dead-code elimination dropped the sign and keypair code
paths cleanly, leaving only the verify-reachable subset plus shared
NTT/poly helpers:

| Build                        | Raw    | Gzipped |
|------------------------------|--------|---------|
| Default (Ed25519 only)       | 142.5 KB | 40.3 KB |
| `-Dpq-wasm=true` (PQ verify) | 171.3 KB | 50.1 KB |
| **Delta**                    | **+28.7 KB raw** | **+9.9 KB gzipped** |

~10 KB over the wire is well inside the 150 KB budget. The prior
"~250–400 KB" estimate was pessimistic by an order of magnitude;
it assumed no DCE and the full OQS_KEM + OQS_SIG dispatch surface.

**End-to-end confirmed.** Mint → hybrid-sign a tool DreamBall via
the native CLI, load `jelly.wasm` in Bun, push bytes through
`verifyJelly`, return code = 2 (Ed25519 + ML-DSA both OK). See
`/tmp/pq-wasm-verify-smoke.ts` during the spike — not committed to
the repo, reconstruct from this note if needed.

**Path forward.**
- ✅ Closed 2026-04-22 — `-Dpq-wasm=true` is now the default; PQ verify
  ships in every `zig build wasm` output. KAT fixture committed; Vitest
  primitive tests green (S1.1 AC1–AC5).
- Open polish: strip internal `pqcrystals_*_internal` + `OQS_SHA3_*`
  symbols from the export table (`wasm_exe.rdynamic` leaks them).
  Not correctness-affecting; a few hundred bytes.
- Signing in the browser remains out of scope by design — user
  signing lives in the key-bearing extension/app path.

### 2. `zstd` compression for DragonBall sealed bundles

**State.** `seal --compress` currently errors with a clear diagnostic.
`std.compress.zstd` in Zig 0.16 only supports decompression, not
compression.

**Why deferred.** A pure-Zig zstd compressor does not yet exist in the
ecosystem. Vendoring `facebook/zstd` as C dep would work but adds a
platform-specific build step.

**Path forward.** Revisit when a pure-Zig zstd compressor lands in
Zig's stdlib (targeted for 0.17+). Alternative: accept bundle-size
overhead of vendoring a C zstd and add a `--with-zstd` build flag.

### 3. Chained proxy-recryption (Guild A → Guild B → recipient)

**State.** `jelly.transmission` receipts today reference one Guild.
Cross-Guild chained delegation is not implemented.

**Why deferred.** FR52/Vision-tier from the original v2 PRD. Requires
design work on multi-hop recryption semantics in `recrypt` itself.

**Path forward.** Spike in `recrypt`'s issue tracker; when the Rust
side has multi-hop support, wire it into `jelly-server`'s transmission
flow.

### 4. Partial WASM write-ops: `sealRelic`, `unlockRelic`, `transmitSkill`

**State.** `jelly.wasm` exports `mintDreamBall`, `growDreamBall`,
`joinGuildWasm`. The remaining CLI commands (`seal-relic`, `unlock`,
`transmit`) are called via subprocess from `jelly-server` rather than
WASM exports.

**Why deferred.** These operations involve DragonBall file wrapping +
recrypt-server hops. Inlining them into WASM requires passing more
parameters (recrypt-server URL, guild keyspace credentials) across the
boundary — doable but adds complexity.

**Path forward.** Natural next sprint; convert each to a WASM export
matching the existing pattern.

### 5. `MockBackend.ts` crypto is intentionally mocked

**State.** `src/lib/backend/MockBackend.ts` contains mock crypto with
`TODO-CRYPTO` comments. This is **by design** — the MockBackend exists
specifically to let Storybook + Vitest run without a live backend.

**Not a gap — intentional.** No action required. If someone forgets and
uses `MockBackend` in a production path, the `TODO-CRYPTO: replace
before prod` markers make the mistake visible in review.

---

### 6. Phase D — Real ML-DSA-87 + recrypt guild keyspaces (partial)

**State (updated 2026-04-20).** The Dreamball side of Phase D no
longer needs the HTTP hop. We vendored the ML-DSA-87 subset of
liboqs 0.13.0 directly into `vendor/liboqs/` and the Zig core now
links it at build time:

- `vendor/liboqs/` — pqcrystals-dilithium ref impl (8 .c files) +
  XKCP SHAKE plain-64 backend + 3 hand-rolled files (our
  `oqsconfig.h`, minimal `oqs.h` override, `dreamball_stubs.c`
  providing `OQS_randombytes` via libc and `OQS_MEM_aligned_*` via
  `posix_memalign`). Pin: upstream tag `0.13.0`, via the vendored
  `oqs-sys 0.11.0+liboqs-0.13.0` crate source. See
  `vendor/liboqs/VENDOR.md` for the full pin record and refresh
  procedure.
- `src/ml_dsa.zig` — Zig wrapper exposing `keypair() → Keypair`,
  `sign(sig_out, msg, secret) → usize`, `signAlloc(allocator, msg,
  secret) → []u8`, `verify(sig, msg, pub) → !void`. Four tests pass:
  keypair→sign→verify round-trip, tampered signature, tampered
  message, cross-key rejection (55/55 total, up from 51).
- `build.zig` — C sources compile into the `dreamball` module with
  `-DDILITHIUM_MODE=5 -std=c11`. No separate static library, no
  `b.dependency`, no CMake glue — just vendored files.

Reversed architectural decision: the recrypt-server
`POST /sign/ml-dsa` and `POST /verify/ml-dsa` endpoints exist and
are tested on the recrypt side (`recrypt-server/src/routes/signing.rs`),
but Dreamball never needs them. Dreamball's jelly-server subprocesses
the native `jelly` binary, which has its own direct liboqs link. No
network round-trip, no auth surface for a sign-with-secret endpoint,
simpler deployment.

**CLI wire-up is now complete for DreamBall nodes** (2026-04-20):

- Node format bumped to `FORMAT_VERSION_V3` when the new
  `identity-pq` core field is present. The field carries the
  signer's 2592-byte ML-DSA-87 public key so verifiers can check
  the PQ signature without out-of-band metadata. v1/v2 nodes
  continue to verify unchanged.
- Key file is a raw `recrypt.identity` Gordian Envelope (CBOR tag
  200) carrying both Ed25519 and ML-DSA-87 keypairs. See
  `docs/decisions/2026-04-21-identity-envelope.md` for the adoption
  rationale. No legacy-format support — Dreamball is pre-release,
  so any older `.key` files regenerate with a fresh `jelly mint`.
- `jelly mint` generates a hybrid keypair, embeds `identity-pq`
  in the core, and emits both signatures.
- `jelly grow`, `jelly join-guild`, `jelly transmit` re-sign with
  whichever algorithms the key file provides. Transmission
  nodes do not yet carry `identity-pq` (no core field; tracked
  separately — the sender's pubkey bundle flows out-of-band,
  matching recrypt's public-key-bundle pattern).
- `jelly seal-relic` stays Ed25519-only on the relic wrapper. Per
  policy, ephemeral wrappers in lower-stakes contexts trust the
  inner DreamBall's own hybrid signature.
- `jelly verify` checks each `'signed'` attribute against the
  appropriate key. Policy: "all attached signatures must verify,"
  no minimum count. Ed25519-only nodes remain valid.

**Two-sig policy — reconciled 2026-04-21.** `PROTOCOL.md §2.3` now
reads "all present signatures must verify, no minimum count" and
`cli/verify.zig` implements the same rule. Ed25519-only nodes are
valid; hybrid nodes require both sigs to verify; an ML-DSA
signature without a matching `identity-pq` in the core is a
verification error (no key to check against). The stricter
recrypt "both required" rule is expected to relax upstream to
match; until then, Dreamball is the reference for the softer
policy.

**What's still pending on the PQ side:**

- Browser-side ML-DSA-87 verification — **spike landed 2026-04-21**
  behind `-Dpq-wasm=true`. +28.7 KB raw / +9.9 KB gzipped over the
  Ed25519-only baseline. Default build stays PQ-free until a
  browser consumer actually needs it. See §1 above for the full
  measurement and follow-ups.
- ✅ Closed 2026-04-21 — `Transmission` and `Relic` envelopes now
  carry their own `identity-pq` slot in core (`sender-identity` +
  `sender-identity-pq` on Transmission, `identity-pq` on Relic)
  so the PQ sig verifies standalone without a pubkey-bundle
  lookup. Envelopes bump to `format-version: 3` when the slot is
  populated. See PROTOCOL.md §12.1.4 and §12.9.

Guild keyspace proxy-recryption (the harder half of Phase D) remains
future work — `recrypt-server` already has keyspace endpoints
(`/keyspaces`, `/recryption/share`), but integrating them into
`seal-relic` and `transmit` is a separate mini-sprint.

**Required recrypt-server changes.**

1. **`POST /sign/ml-dsa`** — signs arbitrary bytes with a caller-supplied
   ML-DSA-87 secret key. Body: `{ secret_key: base58, message: base58 }`.
   Response: `{ signature: base58 }` (~4627 bytes as base58). Uses the
   existing `oqs` crate already wired into `recrypt-core`.

2. **`POST /verify/ml-dsa`** (optional, for browser verify delegation) —
   inverse: `{ public_key, message, signature }` → `{ ok, reason? }`.

3. **Keyspace endpoints for Guild scoping** — recrypt-server already has
   `routes/keyspaces.rs`. Confirm it exposes:
   - `POST /keyspaces` create-new returning a root keyspace handle.
   - `POST /keyspaces/:id/members` add member with a recryption key.
   - `POST /recrypt` server-side recryption under a keyspace scope.

**Required Dreamball wire-up (all scaffolded — flip on when recrypt ready).**

- `jelly-server/src/mldsa-client.ts` — HTTP client hitting the two
  recrypt endpoints. Stub exists; wire real calls when `RECRYPT_SERVER_URL`
  is set at server boot.
- `jelly-server` mint route — two-hop signing: WASM Ed25519, then HTTP
  ML-DSA. Stub exists; flip to real when the endpoint is available.
- `jelly` CLI — gain `--ml-dsa-server <url>` flag. Not yet implemented
  on the CLI; trivial once the HTTP contract is frozen.
- `seal-relic --for-guild` — call `POST /recrypt` with the Guild's
  keyspace ID instead of storing plaintext. Stub exists with a
  `TODO-CRYPTO` marker.
- `unlock` — request recrypted payload from the server, decrypt locally
  with the member's key. Requires a secure member-key custody story (out
  of scope for v2.1 — keys stay as local files for now).

**Dreamball's e2e cryptography test (`tests/e2e-cryptography.sh`)** is
already written; it runs in "mock mode" by default and flips to "real
mode" when `RECRYPT_SERVER_URL` is set. The assertions in real mode
should become live once the recrypt endpoints exist.

**Path forward.**
1. Add `POST /sign/ml-dsa` to recrypt-server (1-2 hrs, Rust changes in
   sibling repo).
2. Wire `jelly-server` two-hop signing (1 hr).
3. Add `--ml-dsa-server` flag to the Zig CLI (1 hr).
4. Confirm `tests/e2e-cryptography.sh` passes in real mode.
5. Keyspace-scoped seal/unlock is a separate mini-sprint after that.

Tracked as **Phase D** of
`.omc/plans/2026-04-19-jelly-server-storybook-mldsa-recrypt.md`.

---

## Resolved in v2.1

These gaps existed before v2.1 and have now closed:

- ✅ **Real Ed25519 signatures in the browser.** `jelly.wasm` imports
  `getRandomBytes` from the host; Ed25519 signing + verification run
  natively in WASM. Browser + server use the same binary.
- ✅ **Real ML-DSA-87 signatures on minted envelopes.**
  `jelly-server`'s mint route orchestrates the two-hop
  WASM-Ed25519 + HTTP-ML-DSA flow via `recrypt-server`.
- ✅ **Guild keyspaces are real recrypt keyspaces.** `mint --type
  guild` creates a real keyspace in `recrypt-server`. `seal-relic` and
  `unlock` use real proxy-recryption.
- ✅ **`HttpBackend` talks to a real server.** The `EdenBackend`
  replacement hits `jelly-server` via typed `treaty<App>` calls.
- ✅ **Identity envelope adopted.** Per-DreamBall key files now use the
  `recrypt.identity` Gordian Envelope (CBOR tag 200) instead of the
  hand-rolled `DJELLY\n` hybrid layout. Byte-identical interop with
  recrypt, tested against three vendored fixtures. See
  `docs/decisions/2026-04-21-identity-envelope.md`. The encrypted
  wallet container (`DCYW` shell around a multi-identity envelope) was
  explicitly NOT adopted — Dreamball has no multi-identity concept per
  DreamBall, so that complexity isn't warranted.

---

## How to add a gap

If you encounter a deferred item during a sprint:

1. Add an entry here with: State / Why deferred / Path forward.
2. Add a `TODO-CRYPTO:` comment in the source with a one-line pointer
   to this file.
3. If the deferred item is security-sensitive, add a CI check that
   fails on accidental removal of the marker.
4. Note the gap in the sprint's PRD under "Assumptions & Risks."

The goal: every residual compromise is visible, dated, and owned.

### NFR11 K-NN relaxation (added by S2.1 HARD BLOCK)

**State**: HARD BLOCK detected by S2.1 parity spike (2026-04-22).

**Why**: kuzu-wasm@0.11.3 browser QUERY_VECTOR_INDEX returned fps not matching
@ladybugdb/core server ground truth. D-015 set-equality contract violated.

**NFR11 relaxation**: K-NN queries in the browser must route to jelly-server
HTTP /kNN endpoint. Offline K-NN is degraded for MVP. Epic 6 must add the
/kNN route.

**Path forward**: S2.3 implements HTTP fallback kNN; S6.3 adds /kNN endpoint.
TODO-KNN-FALLBACK markers must be preserved until both stories land.

