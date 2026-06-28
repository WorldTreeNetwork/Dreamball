---
id: B3
epic: B
title: loader.ts authorAction + verifyAction wrappers (browser + Bun)
status: ready
test_tier: smoke
decisions: [D-042, D-023]
frs: [FR7]
closes_beads: [Dreamball-pky, Dreamball-t2d]
---

# B3 — `loader.ts` `authorAction` + `verifyAction` wrappers

## Context

B1 landed `authorAction` in `wasm_main.zig` (Dreamball-1mo, CLOSED). The WASM
export is callable but `loader.ts` has no typed wrapper for it — callers must
drop to raw `WebAssembly.instantiate`, duplicate the alloc/copy/unpack
boilerplate, and handle the packed-u64 convention by hand (the same gap that
existed for `signActionEnvelope` before sprint-002).

This story adds the JS-ergonomic surface. Two functions are in scope:

- **`authorAction`** — marshals the nine WASM parameters, concatenates parent
  hashes into linear memory, returns signed envelope bytes. The ergonomic
  signature hides all pointer arithmetic from callers.
- **`verifyAction`** — wraps B2's `verifyAction` WASM export using the same
  alloc/copy/unpack pattern as the existing `verifyBall` wrapper.

Subsumes **Dreamball-t2d** (mint/grow/lastSecret typed wrappers): those three
exports follow the same pattern and are bundled here because they share the same
loader seam. They are lower-complexity than `authorAction` (no parent-hash
concatenation, no BigInt HLC params) so they fit naturally in the Task
Breakdown without expanding the ACs.

Both functions must work identically in Bun and the browser — there is one
loader path and one WASM binary; no runtime branching is needed or permitted.

B4 (Dreamball-0ii) owns the thorough Vitest suite. B3's test tier is smoke
only: a manual round-trip through the JS wrappers confirms the plumbing is
correct.

## Acceptance Criteria

1. **`authorAction` wrapper round-trips.** Calling the TS `authorAction`
   wrapper with a valid `kind`, optional `body`, `parents`, `hlc`, and `secret`
   returns a `Uint8Array` of signed envelope bytes whose embedded Ed25519
   signature verifies against the actor derived from `secret[32..64]`. A Bun
   smoke script (or an adapted `scripts/server-smoke.sh` step) confirms this
   without a full Vitest run.

2. **`verifyAction` wrapper validates.** Calling the TS `verifyAction` wrapper
   with the bytes returned by AC1 returns `{ ok: true }`. Passing the same
   bytes with one bit flipped returns `{ ok: false, reason: string }`. (Blocked
   on B2 landing; skeleton may be merged before B2 with a `// TODO: B2` guard
   and the wrapper body throwing `"verifyAction: B2 not yet landed"`.)

3. **Error path throws with message.** Passing an empty-string `kind`, a
   `secret` of wrong length, or an `alloc`-failed input causes the wrapper to
   throw an `Error` whose message includes the WASM diagnostic string read from
   `resultErrPtr`/`resultErrLen`. JS-side pre-validation throws before the WASM
   call for `secret.length !== 64` and empty `kind`, mirroring the guard in
   `signActionEnvelope`.

## WASM ABI (reference — do not re-derive)

The `authorAction` export signature as it exists in `src/wasm_main.zig`
(landed, B1):

```zig
export fn authorAction(
    kind_ptr: u32, kind_len: u32,
    body_ptr: u32, body_len: u32,          // 0/0 = no body
    parent_hashes_ptr: u32, parent_hashes_count: u32,  // count of 32-byte hashes, NOT byte length
    hlc_l: u64, hlc_c: u64,               // i64 in WASM type system → BigInt in JS
    secret_ptr: u32,                        // exactly 64 bytes; NO secret_len param
) u64  // packed (ptr << 32) | len; 0 = error
```

`secret` is the 64-byte Ed25519 secret in Zig wire format `[seed(32) || pub(32)]`
— the same format `mintDreamBall` writes to `last_secret`. The actor fingerprint
is derived inside the export as `secret[32..64]` (D-042); it is NOT a separate
parameter.

Error convention: result `0n` means failure; read the diagnostic with
`resultErrPtr()` / `resultErrLen()` (same pattern as `signActionEnvelope`,
`parseBall`, etc.).

## `WasmExports` interface additions

Extend the `WasmExports` interface in `loader.ts`:

```typescript
// Added by B3
authorAction: (
  kind_ptr: number, kind_len: number,
  body_ptr: number, body_len: number,
  parent_hashes_ptr: number, parent_hashes_count: number,
  hlc_l: bigint, hlc_c: bigint,
  secret_ptr: number,
) => bigint;
// Added by B2 — B3 wraps this; ABI confirmed when B2 ships
verifyAction: (ptr: number, len: number) => number;
// Added by B3 (subsumes Dreamball-t2d)
mintDreamBall: (type_id: number, name_ptr: number, name_len: number, created: bigint) => bigint;
growDreamBall: (
  env_ptr: number, env_len: number,
  secret_ptr: number, secret_len: number,
  new_name_ptr: number, new_name_len: number,
  updated: bigint, promote_to_dreamball: number,
) => bigint;
joinGuildWasm: (
  env_ptr: number, env_len: number,
  guild_env_ptr: number, guild_env_len: number,
  secret_ptr: number, secret_len: number,
  updated: bigint,
) => bigint;
lastSecretPtr: () => number;
lastSecretLen: () => number;
```

Note: `hlc_l` and `hlc_c` are `u64` in Zig → `i64` in WASM → **`bigint`** in
TypeScript. Using `number` would silently truncate values above 2^53.

## Ergonomic JS signature

```typescript
export async function authorAction(opts: {
  kind: string;
  body?: Uint8Array;
  parents: Uint8Array[];  // each exactly 32 bytes
  hlc: [bigint, bigint];  // [hlc_l, hlc_c]
  secret: Uint8Array;     // exactly 64 bytes: [seed(32) || pub(32)]
}): Promise<Uint8Array>  // signed envelope bytes (copied out of bump arena)
```

```typescript
export async function verifyAction(envelope: Uint8Array): Promise<VerifyResult>
// reuses the existing VerifyResult type from verifyBall
```

## Marshalling rules for `authorAction`

Follow the pattern of `signActionEnvelope` exactly. In order:

1. JS-side pre-validate: throw if `opts.secret.length !== 64`, or `opts.kind`
   is empty, before touching WASM.
2. `const exp = await getInstance(); exp.reset();`
3. Encode `kind` via `TextEncoder`; `alloc(kind.byteLength)`; copy into WASM memory.
4. If `opts.body` is present: `alloc(body.length)`; copy. Otherwise pass `0, 0`
   for `body_ptr, body_len`.
5. Concatenate parents: `const ph = new Uint8Array(opts.parents.length * 32)`;
   validate each element is exactly 32 bytes (throw otherwise); copy each into
   `ph` at offset `i * 32`. Then `alloc(ph.length)`; copy `ph` into WASM memory.
   Pass `parent_hashes_count = opts.parents.length` (the count of hashes, not
   the byte length).
6. `alloc(64)`; copy `opts.secret` into WASM memory.
7. Call `exp.authorAction(...)`. If result is `0n`: read `resultErrPtr/Len`; throw.
8. Unpack: `ptr = Number(packed >> 32n)`, `len = Number(packed & 0xffffffffn)`.
9. Return `new Uint8Array(exp.memory.buffer, ptr, len).slice()` — the `.slice()`
   is required; the bump allocator is reset on the next `reset()` call and the
   backing buffer becomes invalid.

Note on `alloc` failure: if any `alloc` call returns `0`, throw
`"authorAction: alloc failed (input too large?)"` before calling the WASM
export, consistent with the other wrappers.

## Note on `content_hash`

The `Dreamball-pky` bead description mentions returning a `content_hash` alongside
the signed bytes. The `authorAction` WASM export does not output the content hash
directly — `contentHash(action)` is `blake3(encodeActionV4(action))` and requires
reconstructing the unsigned canonical bytes inside Zig. Computing it from JS after
the fact would require stripping the `signed` attribute from the returned envelope,
which is a further WASM call not yet exposed.

Deferring to a follow-up: a `contentHashAction` WASM export (or a JS post-
processing step using the existing `blake3Hex`) is the right shape, but adding
any new WASM encode/decode path would consume the razor-thin 1775-byte gzip
headroom flagged in B1's close note (see Dreamball-8bk). The `authorAction`
wrapper therefore returns `Uint8Array` only for now. Callers that need the
content hash can derive it once a size-safe path lands.

## Task Breakdown

- Extend `WasmExports` interface with all fields listed above (authorAction,
  verifyAction placeholder, mintDreamBall, growDreamBall, joinGuildWasm,
  lastSecretPtr, lastSecretLen).
- Implement `authorAction` wrapper: JS pre-validation → reset → alloc/copy for
  each arg → call → unpack → slice. Follow `signActionEnvelope` line by line
  for the alloc/copy/error pattern; the only new complexity is the parent-hash
  concatenation step (5 above).
- Implement `verifyAction` wrapper skeleton: if B2 has not landed, export a
  function that throws with a clear `"verifyAction: B2 not yet landed"` message;
  replace the body with the real alloc/call/unpack once B2 ships. Reuse
  `VerifyResult` type and the `resultErrPtr/Len` read pattern from `verifyBall`.
- Implement `mintDreamBall`, `growDreamBall`, `joinGuildWasm` typed wrappers
  (subsumes Dreamball-t2d). These follow the same alloc/copy/unpack pattern as
  the existing `signActionEnvelope` wrapper; `lastSecretPtr`/`lastSecretLen` are
  called after `mintDreamBall` to retrieve the generated secret key.
- Verify both Bun and browser instantiation paths reach the new exports (one
  `getInstance()` singleton; no branching needed, but the smoke test should
  confirm import resolution in both environments).

## Test Plan

**Smoke (B3 gate):** Write or extend a Bun script (e.g. `scripts/loader-smoke.ts`)
that:
- Calls `authorAction` with all-zeros seed, `kind = "worldtree.kanban-card.move"`,
  body `[0x82, 0x01, 0x02]`, one parent hash `0x10 * 32`, HLC `[1_700_000_000_000n, 7n]`.
- Asserts the result is a non-empty `Uint8Array`.
- Passes the result to `verifyAction` (once B2 lands) and asserts `ok: true`.
- Passes a tampered copy (flip byte 0) and asserts `ok: false`.
- Passes `secret` of length 63 and asserts a thrown `Error` with a meaningful
  message.

`zig build smoke` and `scripts/server-smoke.sh` must remain green (no Zig
changes in this story).

**Thorough Vitest:** Delegated to B4 (Dreamball-0ii).

## Files

`src/lib/wasm/loader.ts` — all changes land here. No Zig changes.

Optional: `scripts/loader-smoke.ts` (or extend `scripts/server-smoke.sh`) for
the smoke gate.

## Dependencies

- **B1** (Dreamball-1mo, CLOSED) — `authorAction` WASM export is landed. This
  story is unblocked for the `authorAction` wrapper.
- **B2** (Dreamball-14d, OPEN) — `verifyAction` WASM export. The `verifyAction`
  TS wrapper in this story is blocked on B2; the `authorAction` wrapper and the
  t2d mint/grow wrappers are NOT blocked and can merge first. Coordinate with
  B2's author to confirm the `verifyAction` export ABI (expected: `i32` return
  mirroring `verifyBall`'s 2/1/0/-1 convention; adapt if B2 differs).
- Blocks **B4** (Dreamball-0ii) — Vitest suite for authorAction round-trip
  requires the TS wrapper this story provides.
