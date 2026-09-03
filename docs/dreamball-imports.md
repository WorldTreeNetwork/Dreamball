# Dreamball Imports

The 5 sprint-002-locked host imports that wasm action modules can call.
Per D-033, this surface is locked: adding a new import requires an ADR
amendment (D-NNN), not a story-execution event.

All imports live in the `dreamball` module namespace. Guest code
declares them with `extern "dreamball" fn <name>(...)`. The host
validates the import table against the allowlist before any guest code
runs (SEC1 / `failure_paths.verifyImports`).

## Calling Convention

- All pointer arguments are `i32` (wasm32 linear-memory address,
  treated as `u32` by the host).
- All length arguments are `i32` (treated as `u32` by the host).
- Multi-value returns (`fp`, `encode_cbor`, `read_node`,
  `emit_action_envelope`) are flattened: the primary return is the
  result pointer (`i32`); the secondary length component is written
  by the host into the scratch slot at `scratch_base + 0..4`. Guests
  read the length from that fixed slot after the call returns.
- `now_ms` returns a single `i64` (no secondary slot needed).

## The 5 Imports

### `dreamball.fp`

**Signature**: `(bytes_ptr: i32, bytes_len: i32) → fp_ptr: i32`

**Returns**: pointer to a 32-byte blake3 fingerprint of the named guest
memory slice. The digest is written into the host-managed scratch
region; the pointer is valid until the next scratch allocation.

**Errors**: traps with `outcome: "trap"` if the slice
`[bytes_ptr, bytes_ptr+bytes_len)` is out of guest linear memory
bounds, or if the host scratch region is exhausted.

**Trust**: the host computes blake3 deterministically using the same
algorithm as `src/fingerprint.zig` (Blake3 via `std.crypto.hash.Blake3`).
Identity is guaranteed — the same bytes always produce the same
digest. Guests cannot influence the hash function.

### `dreamball.encode_cbor`

**Signature**: `(value_ptr: i32, value_len: i32) → bytes_ptr: i32`

**Returns**: pointer to the canonical dCBOR byte-string encoding of
the named slice (major type 2, smallest-length header per
`src/dcbor.zig`). The encoded length is written to the scratch slot
at `scratch_base + 0..4`; guests read it after the call. The encoded
bytes are in the scratch region starting at `bytes_ptr`.

Encoding rules for the header byte(s):

| `value_len` range | Header |
| --- | --- |
| < 24 | `0x40 \| len` (1 byte) |
| < 256 | `0x58 <u8 len>` (2 bytes) |
| < 65536 | `0x59 <u16 len BE>` (3 bytes) |
| < 2^32 | `0x5a <u32 len BE>` (5 bytes) |

**Errors**: traps with `outcome: "trap"` if the input slice is out of
guest linear memory bounds, or if scratch space is exhausted.

**Trust**: the host applies the dCBOR canonical encoding algorithm;
guests supply raw bytes and receive back the correctly-headered CBOR
byte string. No guest code can cause a different encoding to be
selected — the header is computed entirely by the host.

### `dreamball.read_node`

**Signature**: `(node_id_ptr: i32, node_id_len: i32) → node_ptr: i32`

**Returns**: pointer to the node's bytes in the host scratch region,
with the byte count in the 4-byte scratch slot preceding `node_ptr`.
Returns `0` (null pointer) when no node with the given id is present —
this is a normal not-found result, not a trap. Guests must check the
return value before dereferencing.

**Errors**: traps with `outcome: "trap"` if the id slice is out of
guest linear memory bounds, or if scratch space is exhausted while
copying node bytes.

**Trust**: the sprint-002 host carries an in-memory `Node` slice
seeded by the host caller (CLI or dreamball-server). The production wiring
is a thin LadybugDB adapter exposing the same interface (D-022
read-side surface). Guests receive whatever bytes the host stores —
the node store is not guest-writable.

### `dreamball.emit_action_envelope`

**Signature**: `(payload_ptr: i32, payload_len: i32) → envelope_ptr: i32`

**Returns**: pointer to the signed envelope bytes in the host scratch
region. The envelope layout is:

```text
[u32 LE: payload_len][payload bytes][64 bytes Ed25519 signature]
```

The total byte count is written to the 4-byte scratch slot preceding
`envelope_ptr`.

**Errors**: traps with `outcome: "trap"` if the payload slice is out
of guest linear memory bounds, if the host OOM allocator fails, or if
the Ed25519 signing primitive fails. If the module fp check in the
sign-and-promote pipeline fails, the outcome is `"fp_mismatch"`. No
partial promotion occurs on any failure — the envelope is either fully
signed and promoted or not promoted at all.

**Trust**: per SEC2, the host signs using the actor keypair held in
`Host.keypair`; the wasm body cannot forge signatures because it has
no access to private key material. The signature is produced inside
the host via `sign_action.signEd25519(keypair, payload)` — the same
primitive `dreamball.wasm`'s `signActionEnvelope` export wraps (D-023) —
then written into the envelope before the host promotes the result to
the emitted log. There is no code path through the host that emits an
envelope without invoking this signing seam.

### `dreamball.now_ms`

**Signature**: `() → i64`

**Returns**: monotonic millisecond timestamp relative to the host's
clock zero (`Host.clock_zero_ms`, set at `Host.init` time). The value
is clamped to `Host.last_now_ms` so it never decreases within the same
host invocation, even on platforms where `std.time.milliTimestamp` may
be non-monotonic.

**Errors**: none. `now_ms` does not trap. Passing any arguments is a
guest contract violation (the import signature declares zero args); the
runtime rejects the call with `outcome: "trap"` if the caller passes
unexpected arguments.

**Trust**: the clock source is `std.Io.Clock.real` (WASI-compatible,
satisfied by both CLI and the browser shim layer per D-032). Guests
cannot set or skew the clock — they can only read it. Monotonicity
within a single host context is guaranteed by the clamp.

## Outcome Values

The structured-log `outcome` field (NFR11 / `failure_paths.zig`) uses
these values for import-level failures:

| Value | Meaning |
| --- | --- |
| `"ok"` | invocation completed successfully |
| `"trap"` | guest trapped (bad memory access, sign failure, OOM) |
| `"import_violation"` | guest declared an import outside the allowlist |
| `"fp_mismatch"` | blake3(wasm\_bytes) ≠ manifest-declared fp |

## Adding a New Import

Per D-033, the surface is locked to these 5 imports for sprint-002.
Adding a 6th import requires a new architecture-decision entry
(D-NNN amendment) per D-025 — NOT a story-execution event. The
`docs/dreamball-imports.md` document updates as part of that ADR
amendment, not as part of an action-implementation story.

Sprint-002 ships exactly these 5 imports; sprint-003+ may expand the
surface, but only via the ADR amendment process described in D-025 and
D-033.
