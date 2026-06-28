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
