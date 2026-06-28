---
id: A5
epic: A
title: Zig unit tests — v4 tamper matrix + v3 regression guard
status: ready
test_tier: thorough
decisions: [D-037, D-039, D-043]
frs: [FR3, FR5, FR10]
closes_beads: [Dreamball-rfx]
---

# A5 — Zig unit tests: v4 tamper matrix + v3 regression guard

## Context

A2 added five tests covering the happy path: v4 round-trip with and without body, large-HLC
attribute combinations, v3-dispatch regression, and encode-side body-canonicality rejection.
This story owns the **tamper matrix** — the set of structurally invalid or policy-violating
byte streams that `decodeAction` must reject with a specific error, plus the regression guard
that confirms valid v3 decode paths survive the new validation additions A3 introduces.

A3 implements two additional decode-side rejection rules:

1. Empty `kind` string (`""`) in a v4 envelope → `DecodeError.InvalidValue`
2. `body` key present in the core map of a v3 envelope → `DecodeError.InvalidValue`

A5 tests both of those paths and therefore **must execute after A3 lands** for AC4 and AC5.
The remaining tamper cases (HLC arity, unknown version, truncation, missing fields, v4
non-canonical ordering) do not depend on A3 and can be written and verified immediately.

A5 must not duplicate any test A2 added. The five A2 tests (`encodeActionV4 round-trip with
body`, `… without body`, `multi-parent + deps + nacks + target-fp + timestamp`,
`decodeAction dispatches on format-version: v3 envelope still decodes (regression)`,
`encodeActionV4 rejects a non-canonical body`) are preserved untouched.

## Acceptance Criteria

Each AC corresponds to one named test function in `src/envelope_v2.zig`. Tests use
`std.testing.expectError` to assert the exact error variant unless noted.

1. **HLC arity = 1 element**: hand-craft a v4 `ball.action` envelope whose `"hlc"` core-map
   value is a 1-element CBOR array `[l]`. `decodeAction` must return
   `DecodeError.InvalidValue`. Rationale: D-039 mandates exactly `[l, c]`; the decoder
   checks `arr_n != 2` before reading the pair.

2. **HLC arity = 3 elements**: same construction with a 3-element array `[l, c, extra]`.
   `decodeAction` must return `DecodeError.InvalidValue`.

3. **Unknown format-version (5)**: hand-craft a `ball.action` core map with
   `format-version: 5`. `decodeAction` must return `DecodeError.InvalidValue` — the
   `fv == 4` / `fv == 3` dispatch falls through to the `else` arm at `src/envelope_v2.zig:880`.

4. **Empty kind string** _(A3-gated)_: hand-craft a v4 envelope with `"kind": ""`. After A3
   adds the empty-kind guard, `decodeAction` must return `DecodeError.InvalidValue`. The test
   body must compile before A3 lands; use a `if (false) return` stub with a comment
   `// TODO: remove stub once A3 lands`.

5. **Body key present in a v3 envelope** _(A3-gated)_: hand-craft a 5-key v3 core map
   (the normal palace shape: `type`, `actor`, `action-kind`, `parent-hashes`,
   `format-version`) that also carries a `"body"` byte-string key in the same map. After A3
   adds the cross-version body-rejection guard, `decodeAction` must return
   `DecodeError.InvalidValue`. Mark A3-gated as above.

6. **Truncated core map**: encode a valid v4 action with `encodeActionV4`, then pass
   `bytes[0 .. bytes.len / 2]` to `decodeAction`. Must return `DecodeError.Truncated`. Note:
   truncation after the `assertCanonical` prefix may fire as `Truncated` or
   `UnexpectedMajorType` depending on cut point; either is acceptable — assert
   `std.testing.expectError(error.Truncated, ...)` OR inspect the union and accept any error.
   Prefer constructing the truncation at a point inside the core map (past the outer envelope
   and array header) so that `assertCanonical` passes but the map read fails.

7. **Garbage bytes**: pass `&[_]u8{ 0x00, 0x01, 0x02 }` (not a valid CBOR envelope tag) to
   `decodeAction`. Must return any `DecodeError`. Use
   `try std.testing.expect(decodeAction(allocator, &bad) != null)` or
   `std.testing.expectError` with a concrete error if the implementation is deterministic;
   a comment noting which check fires first is sufficient documentation.

8. **Non-canonical map ordering in v4 core map**: hand-craft a 7-key v4 core map where two
   length-4 keys are emitted out of canonical order — e.g., emit `"type"` before `"kind"`
   (violating the canonical `"body" < "kind" < "type"` lex order at length 4). `decodeAction`
   must return `DecodeError.NonCanonicalInteger`, caught by the `assertCanonical` gate at the
   top of `decodeAction`. The existing `HIGH-1: decodeAction rejects non-canonical map-key
   ordering` test covers the v3/5-key shape; this AC covers the v4/7-key shape explicitly.

9. **Missing `hlc` in v4**: hand-craft a 5-key v4 core map (omit the `"hlc"` entry; all
   other required fields present; no `body`). `decodeAction` must return
   `DecodeError.MissingField` (the `if (!hlc_present) return DecodeError.MissingField` arm
   at `src/envelope_v2.zig:858`).

10. **Missing `kind` in v4**: hand-craft a 5-key v4 core map omitting the `"kind"` entry
    (retain `hlc`). `decodeAction` must return `DecodeError.MissingField` (the
    `open_kind_opt orelse return DecodeError.MissingField` arm).

11. **Missing `actor`**: hand-craft a 5-key v4 core map omitting `"actor"`. `decodeAction`
    must return `DecodeError.MissingField` (the `actor_opt orelse return DecodeError.MissingField`
    arm at `src/envelope_v2.zig:883`).

12. **Missing `format-version`**: hand-craft a v4 core map omitting `"format-version"`.
    `decodeAction` must return `DecodeError.MissingField` (the
    `format_version orelse return DecodeError.MissingField` arm at `src/envelope_v2.zig:851`).

13. **v3 golden regression guard**: for each of the three v3 golden action fixtures in
    `src/golden.zig` (fixture 4 — `palace_minted` single-parent; fixture 5 — `move`
    multi-parent; fixture 5a — `inscription_updated` with deps + nacks), build the same
    `v2.Action` struct the golden test uses, encode via `encodeAction` (the v3 path), pass the
    bytes to `decodeAction`, and assert: `result.action.kind` matches the expected wire string;
    `result.action.actor` first byte matches; `result.parent_hashes.len` matches. This verifies
    that A3's decode-side addition rules do not accidentally break the valid v3 paths the golden
    fixtures exercise. (The `src/golden.zig` tests pin only the *encoded* output hash; this AC
    exercises the *decode* round-trip for those same inputs.)

## Task Breakdown

- **AC1–3, 6, 8**: hand-craft invalid byte streams using `zbor.builder` primitives, following
  the pattern of `test "HIGH-1: decodeAction rejects non-canonical map-key ordering"` at
  `src/envelope_v2.zig:2430`. Allocate via `std.Io.Writer.Allocating`, call `toOwnedSlice`,
  defer free, then call `std.testing.expectError`.
- **AC4–5 stubs**: write the full test body but guard the assertion with `if (false) return;`
  and a `// TODO: remove stub once A3 lands` comment. This keeps them in-tree and compiling
  while A3 is open. Remove the guard when A3 closes.
- **AC7**: call `decodeAction(allocator, &bad_bytes)` inside
  `_ = decodeAction(...) catch return;` or `expectError` — simplest form is acceptable.
- **AC9–12**: for each, emit a valid outer envelope tag and 1-element outer array, then a leaf
  tag and an N-key core map (N = required count minus 1), writing every required key-value pair
  except the omitted one. Emit zero attributes. The missing-field error fires during the
  version-resolution block, not during the map scan, so the map count must be exact.
- **AC13**: reuse the `v2.Action` literals verbatim from `src/golden.zig` tests 4, 5, and 5a
  (or factor them via helper functions if golden.zig already has helpers). No golden-hash
  assertion needed — only the decode-result field checks described above.
- Every test that allocates must defer-free every `result.parent_hashes`, `result.deps`,
  `result.nacks` slice (matching the pattern A2's tests use).

## Test Plan

All tests live in `src/envelope_v2.zig` as `test "..."` blocks, following the file's existing
inline style. Suggested names:

```
test "A5: decodeAction rejects hlc arity 1" { ... }
test "A5: decodeAction rejects hlc arity 3" { ... }
test "A5: decodeAction rejects unknown format-version 5" { ... }
test "A5: decodeAction rejects empty kind (A3-gated)" { ... }
test "A5: decodeAction rejects body key in v3 envelope (A3-gated)" { ... }
test "A5: decodeAction rejects truncated core map" { ... }
test "A5: decodeAction rejects garbage bytes" { ... }
test "A5: decodeAction rejects non-canonical v4 map key ordering" { ... }
test "A5: decodeAction missing hlc returns MissingField" { ... }
test "A5: decodeAction missing kind returns MissingField" { ... }
test "A5: decodeAction missing actor returns MissingField" { ... }
test "A5: decodeAction missing format-version returns MissingField" { ... }
test "A5: v3 golden fixtures decode correctly (regression guard)" { ... }
```

Gates after implementation:

```
zig build test      # all 13 tests (AC4/AC5 stubs skip silently)
zig build smoke     # CLI end-to-end — must remain green
```

## Files

`src/envelope_v2.zig` — the only file that changes.

## Dependencies

- **A1** (done) — v4 struct definition.
- **A2** (done) — `encodeActionV4` / `decodeAction` functions under test.
- **A3** (blocks AC4 and AC5) — adds empty-kind and body-on-v3 decode-side rejection.
  AC1–3, AC6–13 can be written and run before A3 lands; AC4–5 use stubs until A3 closes.
  Recommend landing the non-gated tests immediately, then removing the stubs when A3 merges.
- Blocks nothing downstream directly; C1 and B1 rely on a tamper-resistant decode path
  being fully tested before ship.

---

## Dev Agent Record

**Date**: 2026-06-28
**Agent**: exec-A5 (aexec-A5-e648a6c87ce10fc1)

### Tamper cases added

5 new tests added to `src/envelope_v2.zig` (all `test "A5: ..."` blocks):

- **AC5** (`"A5: decodeAction rejects body key in v3 envelope"`): body_opt null guard
  added to the `fv == 3` branch of `decodeAction` (2-line production change + test).
  A3 did NOT implement this guard; it was added here alongside the AC5 test.
- **AC6** (`"A5: decodeAction rejects truncated core map"`): encodes a valid v4 action,
  passes `bytes[0..len/2]`; assertCanonical fires `DecodeError.Truncated`.
- **AC7** (`"A5: decodeAction rejects garbage bytes"`): `[0x00, 0x01, 0x02]` → any
  DecodeError accepted; `readEnvelopeHeader` fires `UnexpectedMajorType` first.
- **AC8** (`"A5: decodeAction rejects non-canonical v4 map key ordering"`): 7-key core
  map (hlc, body, **type**, **kind**, actor, parent-hashes, format-version) — "type"
  before "kind" at len 4 violates canonical lex order; assertCanonical returns
  `NonCanonicalInteger`.
- **AC13** (`"A5: v3 golden fixtures decode correctly (regression guard)"`): three sub-cases
  (fixtures 4 / 5 / 5a) in one test block; asserts kind string, actor first byte,
  parent_hashes.len.

### Dedup vs A2/A3

AC1–4 and AC9–12 are fully covered by A3's 13 tests and HIGH-1 (for AC8's v3 shape).
A5 adds only the 5 non-duplicate cases above.

AC5 required a 2-line production addition to `decodeAction` (body_opt guard in the v3
branch) because A3's implementation omitted it. This is within A5's file scope
(`src/envelope_v2.zig`).

### Gate results

- `zig build` — exit 0
- `zig build test --summary all` — **222/222 tests passed** (baseline 217, +5)
- `zig build smoke` — all smoke checks passed

### No stubs or skips

Zero `if (false)`, `test.skip`, or unimplemented branches. All 5 A5 tests are fully
implemented and live assertions.

### Blocker Type: none

### Blocker Detail: —

### File List

- `src/envelope_v2.zig` — body_opt guard in decodeAction v3 branch + 5 A5 test blocks
