---
id: A2
epic: A
title: v4 encodeAction / decodeAction (7-key core map, CBOR-in-CBOR body, HLC array)
status: ready
test_tier: thorough
decisions: [D-037, D-043, D-039]
frs: [FR3, FR5, FR10]
closes_beads: []
---

# A2 — v4 `encodeAction` / `decodeAction`

## Context
With the v4 struct (A1) in place, extend the codec (`src/envelope_v2.zig:544`
`encodeAction`, and `decodeAction`) to emit/read the v4 wire shape, preserving the
v3 path as a regression. dCBOR determinism (`src/dcbor.zig`) must hold.

## Acceptance Criteria
1. **v4 core map has 7 keys**, emitted in dCBOR length-first order:
   `hlc`(3) · `body`(4) · `kind`(4) · `type`(4) · `actor`(5) · `parent-hashes`(13)
   · `format-version`(14). Among equal length: `body` < `kind` < `type` lexically.
   (Note the v3 key `action-kind` is replaced by `kind` in v4.)
2. `kind` encodes as a CBOR text string; `body` (when present) encodes as a CBOR
   **byte string wrapping the consumer's canonical CBOR** (CBOR-in-CBOR, D-043);
   `hlc` encodes as a 2-element CBOR array of unsigned ints (shortest-form, no tag).
3. `format-version` emits `4`. `deps`/`nacks`/`target-fp`/`timestamp` remain as
   attributes exactly as v3.
4. `decodeAction` dispatches on `format-version`: `4` → v4 reader (kind/body/hlc),
   `3` → existing v3 reader **unchanged** (regression preserved).
5. v4 decode returns the body as raw `[]const u8` (not parsed).
6. Round-trip is canonical: `decode(encode(a)) == a` byte-for-byte; output passes
   `assertCanonical`.

## Task Breakdown
- Extend `encodeAction` to branch on `format_version` (or always emit v4 for v4
  structs); add the three new keys in correct sorted position; embed body via a
  byte-string writer after `assertCanonical(body)` (A3 owns the rejection path,
  but encode must not emit a non-canonical body).
- Extend `decodeAction`: read 7-key map for v4; keep v3 arm; map `kind`/`body`/`hlc`.
- Ensure HLC array uses `dcbor` shortest-int writers.

## Test Plan
- Zig tests: v4 round-trip with body, without body (null), multi-parent_hashes,
  HLC values (small + large `l`); v3 envelope still decodes identically (regression
  vector). `zig build test` + `zig build smoke` green.

## Files
`src/envelope_v2.zig` (+ `src/dcbor.zig` only if a helper is missing).

## Dependencies
A1. Blocks A3, A5, B1, C1.
