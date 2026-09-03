---
id: A3
epic: A
title: Validation on decode (canonical + required fields)
status: ready-for-dev
test_tier: thorough
decisions: [D-041, D-043, D-039]
frs: [FR4]
closes_beads: [Dreamball-8p8]
---

# A3 — Validation on decode (canonical + required fields)

## Context

With the v4 codec in place (A2), `decodeAction` already enforces a subset of
the v4 validation rules. Specifically it enforces: outer-envelope dCBOR
canonicality (`assertCanonical` at entry, `envelope_v2.zig:750`), presence of
`format-version` / `kind` / `actor` / `hlc` (each `MissingField` if absent),
`hlc` array-arity of exactly 2 elements (`InvalidValue` otherwise), and the v3
closed-enum check on `action-kind`.

Two gaps remain that a hand-crafted or mutated envelope can exploit past the
current checks:

1. **Empty `kind` is not rejected.** §18.1 says "Zero-length `kind` is a
   decode error." The current code returns `open_kind_opt` as-is; `kind = ""`
   passes through to the caller.
2. **Body canonicality is not checked on decode.** The encoder calls
   `assertCanonical(body)` before embedding (line 664 in
   `encodeActionV4Signed`), but the decoder reads the body byte-string and
   returns it raw without re-validating. A hand-built envelope can smuggle a
   non-canonical body past decode. D-041 designates Zig `decodeAction` as the
   validation gate of record, which requires the check to also live here.

A3 closes both gaps. A5 owns the broad tamper/fuzz test matrix; A3 owns the
validation logic that makes those tests pass.

## Acceptance Criteria

1. **Empty `kind` rejected.** v4 decode returns `DecodeError.InvalidValue` when
   the `kind` field is a zero-length CBOR text string. Any non-empty valid UTF-8
   string is accepted (the dot-namespace convention is not enforced at the wire
   level per D-038/§18.2).
2. **Non-canonical body rejected.** When a v4 envelope carries a `body` field,
   `decodeAction` calls `assertCanonical(body_bytes)` in the v4 resolution arm
   immediately after assigning `decoded_body`. A body that fails canonicality
   returns the mapped `DecodeError`. Absent body (`body_opt == null`) is
   unaffected.
3. **HLC arity enforced (regression — must stay).** An `hlc` array with != 2
   elements returns `DecodeError.InvalidValue`. Both elements must parse as
   unsigned ints; wrong major type returns the mapped CBOR error. (Already
   enforced by A2; AC3 pins it as a regression gate.)
4. **All required v4 fields present.** Missing `kind`, `actor`, `hlc`, or
   `format-version` each return `DecodeError.MissingField`. (Already enforced
   by A2; regression tests required.)
5. **Unknown `format-version` rejected.** Any value other than `3` or `4`
   returns `DecodeError.InvalidValue`. (Already enforced by A2; regression
   test required.)
6. **v3 path validation preserved.** A v3 envelope with a valid `action-kind`
   from the 9-value closed enum still decodes successfully. A v3 envelope with
   an unknown `action-kind` still returns `DecodeError.InvalidValue`. These
   regressions must pass after A3's changes.

## Design Notes

### Where to add the checks

Both additions land in the `fv == v2.Action.format_version` resolution arm of
`decodeAction` (`src/envelope_v2.zig`, the block starting around line 855):

```zig
if (fv == v2.Action.format_version) {
    // existing
    decoded_kind = open_kind_opt orelse return DecodeError.MissingField;
    // ADD: §18.1 — zero-length kind is a decode error
    if (decoded_kind.len == 0) return DecodeError.InvalidValue;
    if (!hlc_present) return DecodeError.MissingField;
    decoded_hlc = hlc;
    decoded_body = body_opt;
    // ADD: D-041/D-043 — body well-formedness gate (defense in depth)
    if (decoded_body) |b| try assertCanonical(b);
```

`assertCanonical` and `mapDecodeError` are already imported as aliases from
`dcbor.zig` (lines 353–357 of `envelope_v2.zig`). No new imports needed. The
function's return type (`!struct{...}`) uses an inferred error set, so `try`
propagates `DecodeError` values correctly, matching the pattern at line 750
(`try assertCanonical(bytes);`).

### Why `assertCanonical` on the body at decode time

`assertCanonical` treats CBOR byte strings as opaque blobs — it does NOT
recurse into their contents. This means the outer-envelope canonicality check
at `decodeAction` entry (line 750) cannot detect a non-canonical body: the body
is embedded as a byte string and the verifier walks past it without inspecting
the inner bytes. The explicit call on the extracted body bytes is therefore
necessary and distinct from the existing top-of-function check.

The encoder asserts on encode (`encodeActionV4Signed` line 664), keeping
non-canonical bodies off a well-behaved producer's wire. The decoder check is
defense in depth required by D-041: any bytes arriving at `decodeAction`,
regardless of origin, must pass the Zig validation gate before the caller
receives a struct with trusted fields.

### Error type mapping

Both new checks use existing `DecodeError` variants — `InvalidValue` for empty
kind, and whichever variant `assertCanonical` propagates via `mapDecodeError`
for a non-canonical body (e.g. `NonCanonicalInteger`, `UnexpectedMajorType`).
No new error values are introduced.

### Boundary with A5

A3 installs the validation logic. A5 owns the broad tamper test matrix
(bit-flipped envelopes, truncated maps, wrong major types at every field, etc.).
A3's own test plan covers the specific new cases (ACs 1–2) plus regressions on
the previously-enforced rules (ACs 3–6). Do not duplicate A5's fuzz-style
coverage here.

## Task Breakdown

- In `src/envelope_v2.zig`, v4 arm of `decodeAction` (around line 857):
  1. After `decoded_kind = open_kind_opt orelse return DecodeError.MissingField;`,
     add `if (decoded_kind.len == 0) return DecodeError.InvalidValue;`.
  2. After `decoded_body = body_opt;`, add
     `if (decoded_body) |b| try assertCanonical(b);`.
- No changes to the v3 arm, the core-map reading loop, the attribute loop, or
  any other function or file.

## Test Plan

All tests are Zig inline `test "..." { ... }` blocks in `src/envelope_v2.zig`
(or a companion `src/envelope_v2_a3_test.zig` if the file already has many
blocks). Run `zig build test` + `zig build smoke` to confirm all gates green.

**New tests — ACs 1 and 2:**
- `test "A3: v4 empty kind is a decode error"` — construct a v4 `Action` with
  `kind = ""`, bypassing the encoder's own assertCanonical by hand-building the
  CBOR bytes directly (or by patching a valid encode output). Call `decodeAction`
  and assert `error.InvalidValue`.
- `test "A3: v4 non-canonical body is rejected"` — build a v4 `Action` whose
  `body` field contains valid but non-canonical CBOR (e.g. an integer encoded
  with a non-minimal byte width, or a CBOR map with keys out of length-first
  order). Hand-build or patch the envelope bytes so the non-canonical body
  survives the outer `assertCanonical` (since it is wrapped in a byte string
  and not inspected there). Assert `decodeAction` returns a decode error.
- `test "A3: v4 absent body decodes cleanly after A3"` — v4 Action with no body
  (6-key core map) round-trips without error after A3's changes. (Regression
  guard ensuring the `if (decoded_body) |b|` guard does not misfire on null.)
- `test "A3: v4 canonical body passes decode"` — v4 Action with a minimal
  known-good canonical body (e.g. a CBOR integer `1` or a shortest-form map)
  decodes without error; returned `body` bytes are byte-identical to the input.

**Regression tests — ACs 3–6:**
- v4 missing `kind` → `error.MissingField`
- v4 missing `actor` → `error.MissingField`
- v4 missing `hlc` → `error.MissingField`
- v4 missing `format-version` → `error.MissingField`
- v4 `hlc` with 1 element → `error.InvalidValue`
- v4 `hlc` with 3 elements → `error.InvalidValue`
- `format-version` = `5` (unknown) → `error.InvalidValue`
- v3 with a valid `action-kind` (`"palace-minted"`) → success
- v3 with an unknown `action-kind` (`"unknown-verb"`) → `error.InvalidValue`

## Files

`src/envelope_v2.zig` only. No new imports; `assertCanonical` and
`mapDecodeError` are already in scope. No changes to `dcbor.zig`,
`protocol_v2.zig`, or generated files.

## Dependencies

A2. Blocks A5 (tamper test matrix expects validation logic to be in place
before exercising it).

---

## Dev Agent Record

**Agent:** exec-A3 (Opus 4.8)
**Date:** 2026-06-28
**Commit:** <!-- not committed per instructions -->
**Notes:**

Implemented exactly as specified. Two additions to the v4 arm of
`decodeAction` (`src/envelope_v2.zig`):

1. After `decoded_kind = open_kind_opt orelse return DecodeError.MissingField;`
   added `if (decoded_kind.len == 0) return DecodeError.InvalidValue;` (§18.1,
   AC1).
2. After `decoded_body = body_opt;` added `if (decoded_body) |b| try
   assertCanonical(b);` with a comment noting the outer gate walks past the
   body byte-string (D-041/D-043, AC2).

No changes to the v3 arm, the core/attribute loops, or any other file.

**Tests added (13):** a private `A3CoreOpts`/`buildA3V4Core` helper builds a
zero-attribute v4 envelope with a canonical, hand-laid core map so a malformed
field reaches `decodeAction` past the outer `assertCanonical` gate. New cases:
empty kind → `InvalidValue`; non-canonical body (`0x18 0x00`) →
`NonCanonicalInteger`; absent body decodes clean; canonical body (`0x01`)
round-trips byte-identical. Regressions: missing kind/actor/hlc/format-version →
`MissingField`; hlc arity 1 and 3 → `InvalidValue`; format-version 5 →
`InvalidValue`; v3 `palace-minted` decodes; hand-built v3 `unknown-verb` →
`InvalidValue`.

**Deviation:** none. The non-canonical-body test confirmed empirically that the
outer `assertCanonical` does not recurse into the body byte-string (the test
asserts the outer envelope passes `assertCanonical`, yet `decodeAction` rejects
via the new inner check) — matching the Design Notes rationale.

**Gates (all green):** `zig build` exit 0; `zig build test --summary all`
217/217 passed (baseline 204 + 13 new); `zig build smoke` "all smoke checks
passed" exit 0.
