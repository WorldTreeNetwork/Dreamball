//! Shared Ed25519 action-envelope signing primitive (D-023).
//!
//! This is the **single seam** through which Dreamball action-envelope
//! signatures are produced. Two callers go through it:
//!
//!   1. `jelly.wasm` (browser/server projection) — `signActionEnvelope`
//!      export in `src/wasm_main.zig`.
//!   2. `jelly` CLI wasm host (Story 5.2 production host) —
//!      `dreamball.emit_action_envelope` in `src/wasm-host/imports.zig`.
//!
//! Per D-023 + 2026-04-25 steering: sprint-002 ships Ed25519-only.
//! ML-DSA-87 dual-sig parameterisation is deferred to the security pass
//! (project memory `project_dreamball_pq_deferred`). When PQ lands, both
//! call sites pick up the new primitive here in one place.
//!
//! Per SEC2: guests cannot reach this function directly. The host (CLI
//! wasm-host or browser jelly.wasm) is the only path; both *always*
//! invoke this seam after staging and before promoting (D-022).

const std = @import("std");

const Ed25519 = std.crypto.sign.Ed25519;

pub const SignError = error{
    InvalidKey,
    SignFailed,
};

/// Produce a 64-byte Ed25519 signature over `payload` using a 64-byte
/// Ed25519 secret-key encoding. Returns `SignError.InvalidKey` if the
/// secret key bytes don't decode; `SignError.SignFailed` on internal
/// signing failure.
pub fn signEd25519(keypair_bytes: [64]u8, payload: []const u8) SignError![64]u8 {
    const sk = Ed25519.SecretKey.fromBytes(keypair_bytes) catch return SignError.InvalidKey;
    const kp = Ed25519.KeyPair.fromSecretKey(sk) catch return SignError.InvalidKey;
    const sig = kp.sign(payload, null) catch return SignError.SignFailed;
    return sig.toBytes();
}

test "signEd25519 round-trips a payload" {
    const seed: [Ed25519.KeyPair.seed_length]u8 = .{0xCD} ** Ed25519.KeyPair.seed_length;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);
    const sk_bytes = kp.secret_key.toBytes();
    const pk_bytes = kp.public_key.toBytes();

    const payload = "shared-sign-action-primitive";
    const sig_bytes = try signEd25519(sk_bytes, payload);

    const sig_arr: [Ed25519.Signature.encoded_length]u8 = sig_bytes;
    const sig_obj = Ed25519.Signature.fromBytes(sig_arr);
    const pk_obj = try Ed25519.PublicKey.fromBytes(pk_bytes);
    try sig_obj.verify(payload, pk_obj);
}

test "signEd25519 rejects malformed secret key" {
    // Ed25519 secret keys decode by simple memcpy — `fromBytes` accepts any
    // 64-byte input. The "invalid" path comes from downstream `KeyPair.fromSecretKey`
    // detecting that the public-key half doesn't match. We construct an SK whose
    // public-half is nonsense by overwriting only the last 32 bytes.
    const seed: [Ed25519.KeyPair.seed_length]u8 = .{0x11} ** Ed25519.KeyPair.seed_length;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);
    var bad = kp.secret_key.toBytes();
    bad[63] ^= 0xFF;
    bad[62] ^= 0xFF;
    const result = signEd25519(bad, "x");
    try std.testing.expectError(SignError.InvalidKey, result);
}
