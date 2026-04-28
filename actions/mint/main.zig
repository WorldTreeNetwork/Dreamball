//! `actions/mint/main.zig` — Zig source for the production `mint.wasm`
//! action module (Story 5.4 / D-024 spike-before-promote, FR10).
//!
//! ## Purpose
//!
//! This is the FIRST production wasm action authored under the
//! `dreamball.*` host-import contract (D-033 — locked surface of 5).
//! The action implements the `mint` verb declared in
//! `schemas/memory-palace-0.1.0.json` `x-actions.mint`. When the host
//! invokes our `_start` export:
//!
//!   1. We materialise a small mint payload (a fixed marker plus an
//!      identifier byte) inside our linear memory.
//!   2. We call `dreamball.emit_action_envelope(ptr, len)` — the host
//!      stages the payload, signs via the shared Ed25519 primitive
//!      (`src/sign_action.zig` / D-023 / SEC2), promotes the envelope to
//!      the host's emit log, and returns the canonical envelope bytes.
//!   3. We discard the returned envelope pointer (the host owns the
//!      promoted envelope; the CLI projection layer reads
//!      `host.emitted` directly).
//!
//! ## Import surface (AC7)
//!
//! ONLY `dreamball.*` imports are used. Per D-033:
//!
//!   - `dreamball.emit_action_envelope` — the bridge-pattern (D-022)
//!     wasm seam used here.
//!
//! No `env.*`. No `wasi_snapshot_preview1.*`. The grep audit at
//! AC7 walks the import table of the produced `mint.wasm` and asserts
//! every import is namespaced under `dreamball`.
//!
//! ## SEC2 — guest cannot forge signatures
//!
//! This guest never composes signature bytes itself. The 64-byte
//! Ed25519 signature returned in the envelope is produced inside the
//! host (`src/wasm-host/imports.zig#emit_action_envelope`) by calling
//! `sign_action.signEd25519`, which reaches a private key held in the
//! host. A malicious guest cannot reach the key (no import grants
//! that capability); see `tests/wasm/mint-malicious/main.zig` for the
//! AC8 negative fixture demonstrating this.
//!
//! ## Build
//!
//! Compiled by `zig build mint-wasm` to `actions/mint/mint.wasm`.
//! Target: `wasm32-freestanding`, `ReleaseSmall`. The blake3 of the
//! produced bytes is recorded in
//! `schemas/memory-palace-0.1.0.json` `x-actions.mint.implementation.wasm`
//! and then the schema pin is refreshed (D-029, AC1).
//!
//! ## Lifecycle (D-031)
//!
//! Per D-031 transitive trust: the schema is signed by aspects.sh's
//! signing primitive; the wasm fp lives inside the schema; trusting the
//! schema = trusting the wasm fp. Any change to this source requires:
//!   1. Recompile via `zig build mint-wasm`.
//!   2. Recompute the blake3 fp of `actions/mint/mint.wasm`.
//!   3. Update `schemas/memory-palace-0.1.0.json` `implementation.wasm`.
//!   4. Refresh `schemas/.pins/memory-palace-0.1.0.fp`
//!      (`bun run schemas:pin schemas/memory-palace-0.1.0.json`).

// The single sanctioned host import. Calling convention per
// `src/wasm-host/imports.zig`:
//   args: (payload_ptr: i32, payload_len: i32)
//   result: i32 envelope_ptr (host writes [u32 LE payload_len][payload bytes][64 bytes signature]
//   into the guest's scratch region starting at envelope_ptr).
extern "dreamball" fn emit_action_envelope(
    payload_ptr: [*]const u8,
    payload_len: u32,
) i32;

// Fixed payload baked into the module. Size kept minimal — the action
// surface is tested by the host's per-import unit tests + the AC2/AC6
// end-to-end run; this guest's purpose is "exercise the wasm path with
// a real Zig→wasm compile, no hand-authored bytes."
//
// Per IC2 the produced envelope serialises to the existing signed-action
// envelope shape — we don't introduce new top-level fields. Sprint-002
// scope is the wasm wiring, not the envelope-content fidelity (Story 3.5
// promotes the projection layer to feed the schema-derived inputs).
const PAYLOAD: []const u8 = "dreamball:palace.mint:v1";

export fn _start() void {
    // Call into the host. Discard the returned envelope pointer — the
    // host owns the canonical envelope bytes via `host.emitted` and
    // returns the pointer purely as a convention for guests that need
    // to read back what was signed. We don't.
    _ = emit_action_envelope(PAYLOAD.ptr, @intCast(PAYLOAD.len));
}
