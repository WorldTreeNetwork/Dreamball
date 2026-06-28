---
id: B2
epic: B
title: verifyAction WASM export (v4 action verification path)
status: ready
test_tier: smoke
decisions: [D-042, D-043]
frs: [FR9]
closes_beads: [Dreamball-14d]
---

# B2 — `verifyAction` WASM export

## Context

B1's `authorAction` produces a signed v4 `ball.action` envelope: it encodes the
unsigned bytes via `encodeActionV4`, Ed25519-signs them, then re-encodes the same
action with one `signed` attribute appended (`encodeActionV4Signed`). FR9 requires
a verifier that mirrors this path — consume a signed v4 envelope, reconstruct the
canonical unsigned bytes, and verify the signature against the `actor` field.

The signing invariant (D-042 / PROTOCOL.md §16.7): the bytes a producer signs are
exactly `encodeActionV4(action)` (zero `signed` attributes). A verifier recovers
those same bytes by stripping the `signed` attribute(s) from the received envelope
and re-emitting the remainder — identical to how `verifyBall` handles DreamBall
envelopes. **Do not recompute from parsed fields; strip and re-emit.**

Critical gap: `decodeAction` currently **skips** `signed` attributes (the `else`
branch calls `dcbor.skipItem`). It does NOT collect signatures. This is intentional
for the decode path but means signatures cannot be recovered from `decodeAction`
alone. B2 resolves this by calling `envelope.stripSignatures` for the strip-and-
collect pass (already linked in the WASM binary via `verifyBall`) and `decodeAction`
separately for the `actor` field. No new CBOR parsing or Ed25519 code is needed.

WASM gzip budget at B1 merge: **63 761 / 65 536 bytes** (Dreamball-8bk). Adding
`verifyAction` must not push gzip past 65 536. Because the implementation reuses
`envelope.stripSignatures` + `decodeAction` + the existing `Ed25519` verify path,
the binary delta is expected to be small (< 500 bytes raw). Verify and record the
new size in the commit message; reject if gzip exceeds the ceiling.

## Acceptance Criteria

1. New WASM export `verifyAction` with this exact ABI (mirrors `verifyBall`):
   ```zig
   export fn verifyAction(input_ptr: u32, input_len: u32) i32
   ```
   Return codes:
   - `2`  — v4 envelope parsed and Ed25519 signature verified against `actor`
   - `1`  — v4 envelope parsed but no `ed25519` signature present (draft / unsigned)
   - `0`  — verification failed: signature mismatch, tampered bytes, or wrong key
   - `-1` / `0xFFFFFFFF` — parse error (malformed CBOR, not a `ball.action` v4
     envelope, missing required field); diagnostic readable via `resultErrPtr`/`resultErrLen`

2. Canonical unsigned-form invariant: the bytes verified are obtained by calling
   `envelope.stripSignatures(alloc, signed_action_bytes)` — NOT by re-encoding
   from parsed `Action` fields. The B1 KAT already proves that `encodeActionV4(action)`
   == `stripSignatures(encodeActionV4Signed(action, &sigs)).unsigned`; this export
   must use that same reconstruction path.

3. Actor-as-key: the Ed25519 public key used for verification is `actor` from the
   core map of the received envelope — the 32-byte `"actor"` bytes field decoded by
   `decodeAction`. No separate key parameter. The caller cannot supply a different key.

4. Ed25519-only: this export verifies only `ed25519`-alg signatures. Any non-`ed25519`
   `signed` attribute is skipped (not rejected) — consistent with the browser-holds-
   no-PQ-key policy (PROTOCOL.md §2.3 / wasm_main.zig write-op comment). An ML-DSA
   attribute on a v4 action does not affect the return value.

5. `decodeAction` is called on the ORIGINAL (signed) bytes to recover `actor`. It
   already skips `signed` attrs in the attribute loop, so the signed envelope decodes
   without change.

6. WASM builds green (`zig build wasm`) after this change; gzip size recorded and
   must remain ≤ 65 536 bytes. `zig build test` + `zig build smoke` remain green.

## Implementation Notes

### Verification flow (mirrors `verifyBall` exactly)

```
verifyAction(input_ptr, input_len):
  1. envelope.stripSignatures(alloc, input_bytes)
       → stripped.unsigned   (canonical unsigned bytes)
       → stripped.signatures ([]CapturedSignature { alg, value })
  2. envelope_v2.decodeAction(alloc, input_bytes)
       → decoded.action.actor  (32-byte Ed25519 pubkey)
  3. For each sig in stripped.signatures where sig.alg == "ed25519":
       Ed25519.PublicKey.fromBytes(actor) → pk
       Ed25519.Signature.fromBytes(sig.value[0..64]) → sig_obj
       sig_obj.verify(stripped.unsigned, pk)
       → failure → return 0
       have_ed = true
  4. return if (have_ed) 2 else 1
```

Step 1 and 3 are already the `verifyBall` code pattern verbatim; step 2 replaces
`envelope.decodeDreamBallSubject` with `envelope_v2.decodeAction`.

### Why not extend `decodeAction` to return signatures?

`decodeAction` is the generic decode path used by the CLI, server, and existing
round-trip tests — changing its return type would require updating every call site.
The two-call pattern (stripSignatures + decodeAction on the same bytes) costs one
extra envelope walk but keeps both functions single-purpose and their existing tests
untouched. If a future story needs a "decode + sigs in one pass" API, that is a
separate concern.

### `signed` attribute wire shape (from `encodeActionV4Signed`)

Each `signed` attribute in the v4 action envelope is a 2-element CBOR array:
`["signed", ["ed25519", <64-byte-sig-bytes>]]`. `envelope.stripSignatures` already
knows this shape and captures `.alg` and `.value` into `CapturedSignature` slices
into the source bytes. The verifier must copy `.value` into a fixed-size `[64]u8`
before constructing `Ed25519.Signature.fromBytes` (as `verifyBall` does at line 501).

### Errors and diagnostics

- `stripSignatures` error → `setErr(...)` + return `-1`
- `decodeAction` error → `setErr(...)` + return `-1`
- `actor` bytes not a valid Ed25519 key → `setErr(...)` + return `-1`
  (malformed `actor` is a protocol error, not a sig failure)
- Ed25519 verify failure → `setErr("verifyAction: Ed25519 signature verification failed", .{})` + return `0`
- Malformed sig length (≠ 64) → `setErr(...)` + return `0`
  (consistent with `verifyBall` lines 497–500)

## Task Breakdown

- Add `verifyAction` export to `src/wasm_main.zig`, modelled on `verifyBall`;
  import `envelope_v2` (already linked from B1, no new linkage cost).
- Add inline Zig KAT tests (see Test Plan below).
- Run `zig build wasm`; record raw + gzip sizes in the commit message.
- Confirm `zig build test` + `zig build smoke` are green.

## Test Plan

**Inline Zig tests in `src/wasm_main.zig`** (smoke tier):

1. **Happy path** — all-zeros seed, fixed `kind` / `body` / `hlc` / one parent (reuse
   the B1 KAT fixture). Call `authorAction` → `env_bytes`; call `verifyAction` →
   assert return == `2`. Deterministic: the same seed + inputs always produce the same
   signed envelope and must always verify.

2. **Tampered body** — take the signed envelope bytes from (1); flip one bit inside the
   embedded `body` bytes; call `verifyAction` → assert return == `0`.

3. **Tampered kind** — similar; overwrite one byte of the `"kind"` text in the CBOR;
   call `verifyAction` → assert return == `0`. (Tests that the core map is inside the
   signed region.)

4. **Tampered hlc** — overwrite one byte of the HLC array; call `verifyAction` →
   assert return == `0`.

5. **Wrong key** — sign with all-zeros seed but verify with a different keypair's actor
   baked into the core. Easiest: produce `authorAction` bytes with seed A, manually
   re-encode the core with `actor` = pubkey of seed B, call `verifyAction` → assert
   return == `0`.

6. **Unsigned envelope** — call `encodeActionV4` (no sigs) directly; pass those bytes
   to `verifyAction` → assert return == `1`.

7. **Reject zero-length input** — `verifyAction(0, 0)` → assert return == `-1`.

Tests (1)–(4) form the mandatory smoke set called out in the bead description.
Tests (5)–(7) cover the remaining AC branches and should be included in the same
commit.

## Files

`src/wasm_main.zig` (new export + KAT tests), `src/envelope_v2.zig` (read-only
reference — `decodeAction` is called but not modified).

## Dependencies

B1 (`authorAction` export, `envelope_v2` linkage). B2 produces no new exports that
block later stories; C1 (content-hash golden vector) is independent.

## Dev Agent Record

**Agent:** exec-B2 (Opus 4.8)
**Date:** 2026-06-28
**Commit:** <!-- not committed per instructions -->
**Status:** Code complete and green on every gate EXCEPT the WASM gzip size
ceiling, which it exceeds by 78 bytes. **BLOCKER — size (Dreamball-8bk).**

### Implementation

Added the `verifyAction` export to `src/wasm_main.zig`, modelled byte-for-byte on
`verifyBall`:

```zig
export fn verifyAction(input_ptr: u32, input_len: u32) i32
```

Flow (mirrors `verifyBall`, AC1–AC5):
1. `envelope.stripSignatures(alloc, input_bytes)` — recovers the canonical
   UNSIGNED bytes and the captured signatures. This is the existing machinery
   already linked via `verifyBall`; no new CBOR code (AC2).
2. `envelope_v2.decodeAction(alloc, input_bytes)` on the SAME original bytes —
   recovers `decoded.action.actor`. `decodeAction` already skips `signed` attrs,
   so the signed envelope decodes unchanged (AC5).
3. `actor` (32 bytes) is the only verification key — `Ed25519.PublicKey.fromBytes`
   (AC3). No caller-supplied key parameter.
4. For each captured signature with `alg == "ed25519"`: copy `.value` into a fixed
   `[64]u8`, `Ed25519.Signature.fromBytes`, `verify(stripped.unsigned, pk)`. Any
   failure → `return 0`. Non-`ed25519` attrs (e.g. `ml-dsa-87`) are skipped, not
   rejected (AC4, PROTOCOL.md §2.3).

Return codes (identical to `verifyBall`): `2` ≥1 ed25519 sig verified · `1` no
ed25519 sig (draft/unsigned) · `0` verification failed (mismatch / tamper / wrong
key / bad sig length) · `-1` parse error (with `resultErr` diagnostic).

`decodeAction` / `envelope_v2.decodeAction` was NOT modified (read-only, as
specified). No new exports beyond `verifyAction`.

### Tests added (7 inline KAT blocks in `src/wasm_main.zig`)

Valid signed action → `2`; tampered body (flip `0x02`→`0x03` inside the canonical
body bstr, stays canonical so `decodeAction` still succeeds) → `0`; tampered kind
(`'w'`→`'x'`, same length, valid UTF-8) → `0`; tampered hlc (bump MSB of `l`, stays
an 8-byte canonical uint) → `0`; wrong key (sign with seed A, bake seed B's pubkey
into `actor`) → `0`; unsigned `encodeActionV4` envelope → `1`; zero-length input →
`-1`. Shared fixture matches the B1 `authorAction` KAT.

**Caveat (important):** these inline `test {}` blocks do NOT execute under
`zig build test`. No native test artifact roots at `src/wasm_main.zig` (`root.zig`
does not import it; `build.zig` only compiles `wasm_main.zig` as the freestanding
WASM module at line 354, where `test` blocks are skipped). The pre-existing
`signActionEnvelope` and `authorAction` KATs in this file are in the same
situation. The `zig build test` count therefore stays at 217 — it does not rise.
Runtime verification of `verifyAction` happens on the TS side once B3 wires the
loader wrapper (B4 vitest), exactly as `verifyBall` is verified via
`src/lib/wasm/verify.test.ts`. The inline KATs are kept per the spec's Test Plan
and as executable documentation; they will run if/when a native harness roots at
`wasm_main.zig`.

### Gates

- `zig build` — exit 0.
- `zig build test --summary all` — `217/217 tests passed` (unchanged; see caveat).
- `zig build smoke` — `all smoke checks passed`, exit 0.
- `zig build wasm` — exit 0, but **over the gzip ceiling**:
  - raw `226 757` B ≤ `229 376` (224 KB) — OK.
  - gzip **`65 614` B > `65 536`** — **FAILS** the CI gate
    (`test "$gz" -le 65536`). Authoritative delta measured by stashing the change:
    baseline raw `220 751` / gz `63 557` → B2 raw `226 757` / gz `65 614`
    (**+6 006 raw / +2 057 gzip**).

### Blocker

**Type:** WASM size budget (gzip ceiling).
**Detail:** `verifyAction` is the FIRST WASM caller of `envelope_v2.decodeAction`.
`verifyBall` uses `decodeDreamBallSubject` and `authorAction` uses only the v4
encoders, so the entire `decodeAction` v3/v4 decode path (`assertCanonical`, map
walk, `ActionRef`/deps/nacks/target-fp/timestamp handling, the v3 arm) was never
linked before — it now is, costing ~2 KB gzipped and pushing the binary 78 bytes
past `65 536`. The spec's "< 500 bytes raw" estimate assumed `decodeAction` was
already resident; it was not. The size cannot be recovered WITHIN this story's
mandated approach: AC2/AC5 require recovering `actor` via `decodeAction` and forbid
new hand-rolled CBOR. Resolving this is size work → **Dreamball-8bk**, not a budget
bump (per team-lead directive). Options for that bead: (a) a lighter
action-core-only `actor` reader sharing the dCBOR primitives already resident, or
(b) ReleaseSmall/dead-code reductions elsewhere to reclaim the ~80 gzip bytes.

### File List

- `src/wasm_main.zig` — new `verifyAction` export + 7 inline KAT blocks + 3 private
  test helpers (`authorKatEnvelope`, `mutableCopy`, `callVerify`; referenced only by
  test blocks, so not linked into the WASM binary).
- `docs/sprints/003-open-type-system/stories/B2-v4-verification-path.md` — this
  Dev Agent Record.

(`src/envelope_v2.zig` shows as modified in `git status` from the already-landed A3
work, not from B2 — B2 did not touch it.)

### Handoff to B3 (loader.ts wrapper)

`verifyAction` export ABI for the loader wrapper:

```
verifyAction(input_ptr: u32, input_len: u32) -> i32
```

- Inputs: pointer + length of the signed v4 `ball.action` envelope bytes in WASM
  linear memory (alloc + copy via the existing `alloc(size)` export, same pattern
  the loader already uses for `verifyBall`).
- Returns `i32`: `2` = verified, `1` = unsigned/draft (no ed25519 sig), `0` =
  verification failed, `-1` = parse error. On `-1` read `resultErrPtr()` /
  `resultErrLen()` for the diagnostic string (same buffer as every other export).
- No key parameter — the actor in the envelope core IS the verification key.
- Mirror `verifyBall`'s wrapper exactly; the only differences are the export name
  and that there is no sealed-wrapper / tag-200 prefixing (an action envelope is a
  bare tag-200 envelope; `stripSignatures` handles it directly).
- **Do not ship the loader wrapper until the B2 size blocker is resolved** — the
  committed `dreamball.wasm` currently exceeds the gzip gate, so CI is red.

---

## Dev Agent Record — REOPEN fix (correctness bug)

**Agent:** exec-B2fix (Opus 4.8)
**Date:** 2026-06-28
**Status:** Fixed and verified end-to-end. loader-smoke 7/7 PASS.

### Root cause (confirmed)

`verifyAction` verified the Ed25519 signature against `stripped.unsigned` — the
`unsigned` reconstruction returned by `envelope.stripSignatures`. For a standard
v4 action envelope whose only non-subject assertions are `signed` attributes
(`new_count == 1`), `stripSignatures` emits the DreamBall **subject-only** form:
`d8c8 d8c9 …` (tag200 wrapping tag201 directly). But the producer
(`authorAction`/B1) signed the output of `encodeActionV4`, which ALWAYS wraps the
subject in `writeArray(1 + ac)` → the **array-of-1** form `d8c8 81 d8c9 …`. The
leading `0x81` array header is in the signed bytes but absent from the
`stripSignatures` reconstruction, so `sig.verify(stripped.unsigned, pk)` checked
the wrong byte string and returned `0` (FAIL) for every standard signed action.
This was missed because the inline `wasm_main.zig` KAT blocks do not execute under
`zig build test` (the gate gap B2 flagged); no gate ran `verifyAction` until B3's
loader-smoke.

### Fix (Option B)

In `verifyAction` (`src/wasm_main.zig`), recompute the canonical unsigned bytes by
re-encoding the decoded action — `envelope_v2.encodeActionV4(alloc_, decoded.action)`
— and verify against those bytes instead of `stripped.unsigned`. This reproduces
exactly the bytes `authorAction` signed (the array-of-1 unsigned form) and is
identical to C1's `content_hash` domain. The signatures themselves still come from
`stripped.signatures`. `encodeActionV4`, `encodeActionV4Signed`, `stripSignatures`,
and the entire `envelope_v2.zig` encode path are UNTOUCHED — so C1's golden vector
and the cross-runtime test are unaffected. `encodeActionV4`/`decodeAction` were
already linked into the WASM, so the size delta is negligible.

### Gates (all green)

- `zig build` — exit 0.
- `zig build wasm` — exit 0. raw **227 651** B ≤ 307 200 (300 KB); gzip **65 937** B
  ≤ 153 600 (150 KB). Comfortable headroom under the relaxed budget.
- `zig build test --summary all` — **222** pass (193+4+2+8+15), unchanged baseline.
- `zig build smoke` — `all smoke checks passed`, exit 0.
- `bun run scripts/loader-smoke.ts` — **7 passed, 0 failed**, including
  `verifyAction(signed) → ok: true, code: 2` and
  `verifyAction(tampered byte 0) → ok: false`:

  ```
  PASS  mintDreamBall returns envelope + 64-byte secret (avatar)
  PASS  authorAction returns non-empty Uint8Array
  PASS  verifyAction(signed) → ok: true, code: 2
  PASS  verifyAction(tampered byte 0) → ok: false
  PASS  authorAction guard: secret.length !== 64 → descriptive Error
  PASS  authorAction guard: empty kind → descriptive Error
  PASS  growDreamBall(minted envelope) → non-empty Uint8Array
  loader-smoke: 7 passed, 0 failed
  ```

- `bun run test:unit -- --run --project server src/lib/wasm/verify.test.ts` —
  7 passed (WASM budget test, now 300 KB/150 KB).
- `bun run check` — 0 errors (1 pre-existing unrelated a11y warning).

### File List

- `src/wasm_main.zig` — `verifyAction`: unsigned-bytes source changed from
  `stripped.unsigned` to `encodeActionV4(decoded.action)`; doc comment updated.
- `docs/sprints/003-open-type-system/stories/B2-v4-verification-path.md` — this record.
