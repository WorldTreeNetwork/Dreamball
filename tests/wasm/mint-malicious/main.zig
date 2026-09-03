//! `tests/wasm/mint-malicious/main.zig` — AC8 negative fixture for
//! Story 5.4 (SEC2: guest cannot forge signatures).
//!
//! ## What this guest tries to do
//!
//! A "compromised" mint guest that attempts to fabricate its own
//! signature bytes — i.e., it tries to construct a signed envelope
//! WITHOUT calling `dreamball.emit_action_envelope`. Per SEC2, the
//! private key lives only in the host; the wasm import surface (D-033)
//! exposes no path that returns key material. So the guest can write
//! arbitrary bytes into its own linear memory and CALL them a signature,
//! but those bytes will not verify against the host's public key.
//!
//! ## What the host-side test asserts
//!
//! `tests/wasm/mint-malicious-forgery.test.ts` (or a sibling Zig test)
//! loads this guest, lets it run, then takes the bytes the guest claims
//! are a "signature" and feeds them into Ed25519 `verify` against the
//! host's public key. Verification MUST fail. SEC2 holds: even an
//! adversarial guest cannot produce verifying envelopes.
//!
//! Note: this guest still uses ONLY `dreamball.*` imports — anything
//! else would be rejected at host-load time by the import-violation
//! check (Story 5.3 / D-033). The malice is at the *envelope-content*
//! layer, not at the import-surface layer.

extern "dreamball" fn emit_action_envelope(
    payload_ptr: [*]const u8,
    payload_len: u32,
) i32;

// The guest writes a "fake signature" into its own linear memory at a
// fixed offset and exposes it via a `forged_signature` export. The
// Zig-side test reads instance.memory[forged_signature_addr..+64] and
// asserts it does NOT verify.
//
// We pick 0x1000 to sit clear of the host's scratch region (which lives
// at the start of linear memory, see imports.zig#emit_action_envelope).
const FORGED_SIG_OFFSET: usize = 0x1000;

// Bytes the guest pretends are a valid Ed25519 signature. Any pattern
// that doesn't happen to be a real signature for the message-under-test
// suffices; we use 0xAA-fill so the test asserts deterministically.
const FORGED_SIG_BYTES: [64]u8 = [_]u8{0xAA} ** 64;

// Public so the host can read it back (the guest's storage location for
// "what we claim is a signature").
export fn forged_signature_addr() i32 {
    return @intCast(FORGED_SIG_OFFSET);
}

export fn forged_signature_len() i32 {
    return 64;
}

export fn _start() void {
    // Stash the forged signature bytes at FORGED_SIG_OFFSET so the
    // host can recover them post-invocation.
    //
    // We use a raw pointer write since this is wasm32-freestanding and
    // we have no allocator. The memory at FORGED_SIG_OFFSET is part of
    // our (single-page) linear memory.
    const dest: [*]u8 = @ptrFromInt(FORGED_SIG_OFFSET);
    var i: usize = 0;
    while (i < FORGED_SIG_BYTES.len) : (i += 1) {
        dest[i] = FORGED_SIG_BYTES[i];
    }

    // Optionally still call the legitimate emit path so the host has a
    // signed envelope to compare against. The forged bytes are
    // independent of whatever the host produces.
    const payload: []const u8 = "malicious-mint-payload";
    _ = emit_action_envelope(payload.ptr, @intCast(payload.len));
}
