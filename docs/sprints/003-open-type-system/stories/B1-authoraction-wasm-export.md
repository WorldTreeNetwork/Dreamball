---
id: B1
epic: B
title: authorAction WASM export (link envelope_v2; packed-u64 encode+sign)
status: ready
test_tier: thorough
decisions: [D-042, D-037]
frs: [FR6]
closes_beads: [Dreamball-hp6]
---

# B1 — `authorAction` WASM export

## Context
Per D-042, expose v4 authoring as a single encode+sign WASM call. Today
`wasm_main.zig` imports only v1 `envelope.zig` (TC6); this links `envelope_v2`.
`signActionEnvelope` (raw byte-signer, D-023) is retained unchanged. Resolves the
re-scoped beads `Dreamball-hp6`.

## Acceptance Criteria
1. `src/wasm_main.zig` imports `envelope_v2`; the WASM still builds and the
   existing exports/tests are unaffected.
2. New export with this exact ABI (packed-u64 convention, `0` on error →
   `resultErrPtr/Len`):
   ```zig
   export fn authorAction(
       kind_ptr: u32, kind_len: u32,
       body_ptr: u32, body_len: u32,          // 0/0 = no body
       parent_hashes_ptr: u32, parent_hashes_count: u32,  // count of 32-byte hashes
       hlc_l: u64, hlc_c: u64,
       secret_ptr: u32,                        // 64-byte Ed25519 secret [seed||pub]
   ) u64
   ```
3. Behavior: build a v4 `Action` (actor = `secret[32..64]`), `encodeAction` →
   canonical bytes, Ed25519-sign, wrap as a signed envelope, return packed
   `(ptr<<32)|len`.
4. Errors return `0` with a diagnostic: bad secret length (≠64), zero-length kind,
   non-canonical body, OOM.
5. Record raw + gzip `dreamball.wasm` size after linking (NFR5; soft 300 KB-gz flag).

## Task Breakdown
- Add the import + export to `wasm_main.zig`; reuse the Ed25519 path from
  `mintDreamBall`; marshal parent_hashes from concatenated 32-byte runs.
- Extend `envelope_v2.encodeAction` reuse (from A2) for the signed-wrap step.
- Add a Zig inline KAT mirroring the `signActionEnvelope` test style.

## Test Plan
- Zig: `authorAction` with all-zeros seed + fixed kind/body/hlc → deterministic
  signed bytes; verify via existing verify path; tamper fails. `zig build test` +
  `zig build smoke` + `zig build wasm` green.

## Files
`src/wasm_main.zig`, `src/envelope_v2.zig` (shared encode), `src/golden.zig` (KAT).

## Dependencies
A2 (encoder). Blocks B2, B3, B4, C1.
