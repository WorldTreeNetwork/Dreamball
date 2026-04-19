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
