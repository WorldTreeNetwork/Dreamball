---
id: B4
epic: B
title: "Vitest: authorAction round-trip + verify + tamper, Bun & browser-mode"
status: ready
test_tier: thorough
decisions: [D-042, D-043]
frs: [FR7]
nfrs: [NFR2]
closes_beads: [Dreamball-0ii]
---

# B4 — Vitest: `authorAction` round-trip + verify + tamper

## Context

B1 added `authorAction` as a WASM export; B3 wraps it (and `verifyBall`) in
loader-level TypeScript so callers never touch raw WASM memory. B4 closes the
testing gap: it drives those exports end-to-end — author → verify → tamper →
wrong-key — in both the Bun/node Vitest project (`server`) and the browser
(`client`/chromium), proving identical verdicts across runtimes (NFR2).

The structural pattern is identical to C1: a shared-assertions module holds
all the logic; two thin test files select the runtime and load the WASM binary
differently. The same C1 KAT fixture (`__fixtures__/action-v4.golden.json`) is
reused so the golden inputs stay a single source of truth.

**Browser-leg caveat (Dreamball-nvg).** Playwright's chrome-headless-shell
cannot be extracted locally (disk at 100%). The `.svelte.test.ts` file is
code-complete-by-construction and verified in CI. Do not block this story on
local browser execution. The Bun/node leg is the authoritative local proof.

## Acceptance Criteria

1. **Bun/node leg green locally.** `action-v4-authoraction.test.ts` (routed to
   the `server` Vitest project) passes with `bun run test:unit -- --run` on the
   developer's machine with no environment prerequisites beyond a built
   `dreamball.wasm`.
2. **Browser leg green in CI.** `action-v4-authoraction.svelte.test.ts` (routed
   to the `client`/chromium Vitest project via the `.svelte.test.ts` suffix)
   passes in the GitHub Actions CI environment where Playwright extraction
   succeeds.
3. **Round-trip positive.** `authorAction` with the C1 KAT inputs (all-zeros
   seed, kind `worldtree.kanban-card.move`, body `0x82 01 02`, one parent
   `0x10`×32, hlc `[1700000000000, 7]`) returns a packed-u64 ≠ 0. Passing those
   bytes to `verifyBall` returns code `2` (`VERIFY_OK`, Ed25519 present and
   valid).
4. **Tamper negative.** A one-byte XOR flip in the signed envelope body (before
   the signature attribute) causes `verifyBall` to return code `0`
   (`VERIFY_FAILED`).
5. **Wrong-key negative.** A version of the signed envelope where the 64-byte
   Ed25519 signature bytes have been replaced (e.g., zeroed or swapped in from
   a second `authorAction` call with a different seed) causes `verifyBall` to
   return code `0` (`VERIFY_FAILED`). The actor field names key A; the
   substituted signature cannot verify against key A.

## Task Breakdown

- **Shared module** — `src/lib/wasm/action-v4-authoraction.shared.ts`.
  Define a `WasmAPI` interface that includes all exports touched by this gate
  (`memory`, `alloc`, `reset`, `authorAction`, `verifyBall`, `resultErrPtr`,
  `resultErrLen`). Provide `instantiateWasm` (identical contract to C1's),
  `hexToBytes`, `readPacked`, and an `assertAuthorActionGate(wasm: WasmAPI)`
  function that runs all five sub-cases below:
  - **Round-trip**: call `authorAction` with KAT inputs → `readPacked` →
    `verifyBall(signedBytes)` → assert return code is `2`.
  - **Tamper body**: copy the signed bytes, XOR byte at index `4` (inside the
    core map, well before the signature attribute) → `verifyBall` → assert code
    is `0`.
  - **Tamper trailing byte**: XOR the last byte of the signed envelope →
    `verifyBall` → assert code is `0`. (The last byte is inside the signature
    attribute; this exercises a different parse path from the body tamper.)
  - **Wrong-key (zeroed sig)**: locate the 64-byte Ed25519 signature within the
    signed envelope bytes and zero them out → `verifyBall` → assert code is `0`.
  - **Zero-length kind error**: call `authorAction` with `kindLen = 0` → assert
    the returned packed value is `0n` (error sentinel) and `resultErrPtr/Len`
    yields a non-empty diagnostic string.

- **Bun/node leg** — `src/lib/wasm/action-v4-authoraction.test.ts`.
  Mirror C1's `action-v4-cross-runtime.test.ts` exactly: `readFileSync` the
  WASM path, `instantiateWasm`, single `it` that calls `assertAuthorActionGate`.
  Vitest project: `server` (no `.svelte.test.ts` suffix).

- **Browser leg** — `src/lib/wasm/action-v4-authoraction.svelte.test.ts`.
  Mirror C1's `action-v4-cross-runtime.svelte.test.ts`: dynamic `import(
  './dreamball.wasm?url')` → `fetch` → `instantiateWasm`, single `it` that
  calls `assertAuthorActionGate`. Include the browser-leg caveat comment
  (Dreamball-nvg). Vitest project: `client` (chromium).

- **No new fixture file.** The shared module imports
  `__fixtures__/action-v4.golden.json` (already committed for C1) for the KAT
  inputs. No new JSON is needed.

- **No loader.ts changes.** B3 owns the loader wrappers. B4 tests the WASM
  exports directly (same pattern as C1 and `loader.test.ts`) so the test is
  self-contained and does not depend on Vite's `?url` transform in the Bun leg.

## Test Plan

- `bun run test:unit -- --run --project server` — Bun/node leg must be green.
- CI chromium run — browser leg must be green.
- `zig build test` and `zig build smoke` — must remain green (no Zig changes in
  this story; verify nothing is accidentally broken).
- Intentional one-bit perturbation sub-cases inside `assertAuthorActionGate`
  cover both body and signature regions of the signed envelope.

## Locating the signature bytes in the signed envelope

The signed envelope produced by `authorAction` has this structure (see C1 Dev
Agent Record and `action-v4.golden.json`):

```
[2-byte CBOR tag 0xd8c8] [1-byte array header 0x82]
  [core block — identical to unsigned from offset 3]
  [signed attribute: CBOR array ["signed", ["ed25519", <64-byte-sig>]]]
```

The 64-byte raw Ed25519 signature sits at a fixed negative offset from the end:
`signedBytes.slice(signedBytes.length - 64)`. The spec implementer MUST verify
this offset against `action-v4.golden.json`'s `signedBytesHex` before coding
the wrong-key sub-case. Do not hard-code an offset without confirming it against
the fixture.

## Files

New:
- `src/lib/wasm/action-v4-authoraction.shared.ts`
- `src/lib/wasm/action-v4-authoraction.test.ts`
- `src/lib/wasm/action-v4-authoraction.svelte.test.ts`

Read-only (reused, no modifications):
- `src/lib/wasm/__fixtures__/action-v4.golden.json`
- `src/lib/wasm/action-v4-cross-runtime.shared.ts` (structural reference)
- `src/lib/wasm/action-v4-cross-runtime.test.ts` (structural reference)
- `src/lib/wasm/action-v4-cross-runtime.svelte.test.ts` (structural reference)

## Dependencies

- **B1** (done) — `authorAction` WASM export.
- **B3** (must land first) — loader.ts `authorAction`/verify wrappers. B4 does
  not call the loader wrappers directly (it drives raw WASM like C1), but B3
  must be merged before B4 so the loader surface exists for the integration
  narrative and any future higher-level tests.
- Blocks nothing in sprint-003 (B4 is a leaf in the dependency graph).

## Dev Agent Record

_(filled in after implementation)_
