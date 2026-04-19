# Known Gaps

The residual `TODO-CRYPTO` and deferred-work items in DreamBall, each
tied to an engineering plan or a tracking entry. Every gap must either
resolve to real code or to a deliberate Vision-tier decision — nothing
lingers here without a clear next step.

---

## Active gaps (post v2.1)

### 1. Browser-side ML-DSA-87 verification

**State.** `verifyJelly` in `jelly.wasm` currently verifies Ed25519
locally and acknowledges ML-DSA-87 signatures without verifying them.
Production verification paths use `jelly-server`'s `mlDsaVerifyUrl`
option, which delegates to `recrypt-server`.

**Why deferred.** `std.crypto.sign.Ed25519` works on freestanding-wasm
out of the box; no equivalent ML-DSA-87 exists in Zig 0.16 stdlib.
Options are liboqs-wasm (+1.5 MB bundle) or a pure-Zig port (correctness
risk).

**Path forward.** Revisit when either:
- A trustworthy pure-Zig ML-DSA-87 implementation appears in the 0.17
  stdlib, or
- A vendored liboqs-wasm build becomes a manageable dep.

Tracked as **Growth FR58** in the v2.1 plan.

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

### 6. Phase D — Real ML-DSA-87 + recrypt guild keyspaces (cross-repo sprint)

**State.** Phase D of the v2.1 plan (real post-quantum signing + real
proxy-recryption for Guild keyspaces) is gated on recrypt-server changes
that live in a sibling repository (`/Users/dukejones/work/Identikey/recrypt`).
The Dreamball side is ready to consume these endpoints; the recrypt side
must expose them first.

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
