---
id: C1
epic: C
title: content_hash + cross-runtime golden vector (CLI ≡ WASM)
status: ready
test_tier: thorough
decisions: [D-043, D-039]
frs: [FR8]
nfrs: [NFR1]
---

# C1 — `content_hash` + cross-runtime golden gate

## Context
The whole point of the op log is portable op identity: the same logical v4 action
must hash identically across the Zig CLI, browser WASM, and Bun WASM (NFR1). Per
D-043, `content_hash = Blake3-256(canonical envelope bytes)` with no domain
separation.

## Acceptance Criteria
1. A `content_hash` helper computes `Blake3-256` over the canonical v4 envelope
   bytes (reuse `hashBlake3`; no domain prefix).
2. A **golden vector** in `src/golden.zig` fixes one v4 action (with a non-empty
   `body` and a specific `hlc`) → its exact canonical bytes (hex) and its
   `content_hash` (hex).
3. A test asserts the **Zig CLI** path produces those exact bytes + digest.
4. A **Vitest** asserts the **WASM** path (via `authorAction`/encode) produces the
   **identical** bytes + digest, run under Bun (and jsdom browser-mode) — proving
   CLI ≡ browser ≡ Bun. 0 divergences.
5. The v3 golden vectors are untouched (regression).

## Task Breakdown
- Add the v4 golden fixture (logical value + expected hex) to `golden.zig`.
- Zig test asserting CLI bytes/digest.
- Vitest cross-checking WASM output against the same hex constants (shared fixture
  file the TS test imports).

## Test Plan
- `zig build test` (CLI golden) + Vitest (WASM golden) both green and equal;
  intentional one-byte perturbation flips the hash (negative test).

## Files
`src/golden.zig`, a shared fixture (e.g. `src/lib/generated/__fixtures__/action-v4.golden.json`),
`src/lib/wasm/*.test.ts`.

## Dependencies
A2 (CLI encoder) + B1 (WASM export). Blocks C3 (final gate).

## Dev Agent Record

**Which bytes are hashed (the load-bearing decision).** `content_hash =
Blake3-256(canonical UNSIGNED v4 envelope bytes)`, with **no** domain-separation
prefix (D-043, PROTOCOL.md §16.7/§17.4). The unsigned bytes are exactly what
`envelope_v2.encodeActionV4` emits (`encodeActionV4Signed(a, &.{})`). Signatures
are **not** covered: a verifier strips the `signed` attributes and recomputes
over these same unsigned bytes, identical to how DreamBall envelopes are signed
(PROTOCOL.md §2.3). This is non-obvious because the WASM `authorAction` export
(B1) returns a *signed* envelope, so a naive "hash what authorAction returns"
would hash signature bytes and make the op identity signature-dependent — wrong.

**How CLI ≡ WASM is asserted (the signed/unsigned reconciliation).**
`authorAction` only emits signed bytes, but the content_hash domain is the
unsigned bytes — so the gate locks **three** golden constants and exploits one
structural invariant:
- `GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX` — the content_hash domain.
- `GOLDEN_ACTION_V4_CONTENT_HASH` — `Blake3(unsigned)`.
- `GOLDEN_ACTION_V4_SIGNED_BYTES_HEX` — what `authorAction` returns for the
  all-zeros seed (Ed25519 is deterministic, so this is fixed).
The signed and unsigned encodings share a **byte-identical leaf+core block**;
they differ only in the 1-byte outer-array header and the trailing `signed`
attribute. So everything from offset 3 (2-byte envelope tag + 1-byte array
header) onward is identical between the two up to the core's end. The Zig CLI
test pins all three constants directly (`encodeActionV4`, `contentHash`,
`encodeActionV4Signed`). The Vitest asserts the WASM `authorAction` output is
byte-identical to the signed golden, that its `[3..]` core block equals the
unsigned golden's `[3..]` core block (proving WASM produces the canonical
content_hash domain), and that `Blake3(unsigned)` via the same WASM Blake3 the
CLI uses equals the pinned digest. Transitively, CLI and WASM agree on the
unsigned bytes, the signed bytes, and the digest. This avoided adding a new
unsigned-encode WASM export (the gzip budget is razor-thin at 63761/65536).

**New surface added.** `envelope_v2.contentHash(allocator, action)` — a named
`Blake3(encodeActionV4)` helper so consumers (and the golden test) call one
canonical function rather than re-deriving the domain (AC1). No CLI subcommand
was needed; the gate drives the encoder/`authorAction` directly. The committed
`dreamball.wasm` already exported `authorAction` + `hashBlake3` from B1, so the
binary was **not** rebuilt and its size is unchanged (220751 raw / 63761 gzip).

**Fixture.** The B1 reference KAT, reused for consistency: kind
`worldtree.kanban-card.move`, body canonical CBOR `[1,2]` (`0x82 0x01 0x02`),
one parent `0x10`×32, hlc `[1700000000000, 7]`, actor = Ed25519 public key of
the all-zeros 32-byte seed (`3b6a27bc…59da29`, asserted in the Zig test). Pinned
content_hash: `5b97ee37cd5fc24ee7e88c96d6613dadf9fafe4ebea5429ac328af133e2fd27b`.

**Cross-runtime legs.** The Bun/node leg (`action-v4-cross-runtime.test.ts`,
`server` project) and the browser leg (`action-v4-cross-runtime.svelte.test.ts`,
`client`/chromium project) both call the same `action-v4-cross-runtime.shared.ts`
assertions against the same `dreamball.wasm` (NFR2). The TS-side golden mirror
lives in `src/lib/wasm/__fixtures__/action-v4.golden.json` (not under
`generated/`, which C2 regenerates); the gate forces the Zig and TS copies to
agree, so any drift fails a gate on one side.
