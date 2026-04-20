//! ML-DSA-87 signing via the vendored liboqs 0.13.0 reference implementation.
//!
//! The C sources under `vendor/liboqs/` are compiled and linked into any
//! artifact that uses the `dreamball` module (see build.zig). This file is
//! the only Zig-side surface that reaches into liboqs — everything else uses
//! `keypair` / `sign` / `verify` here.
//!
//! WASM note: these externs do not exist in the wasm32-freestanding build; the
//! WASM path still emits the zero-filled placeholder from `signer.zig` for
//! mint/grow/etc. Browser-minted nodes today carry a placeholder in the
//! ML-DSA `'signed'` attribute and rely on a later server-side ML-DSA pass.
//! See `docs/known-gaps.md`.

const std = @import("std");
const builtin = @import("builtin");

// Sizes match FIPS-204 Category 5 / pqcrystals_ml_dsa_87 constants defined in
// liboqs's api.h. Hard-coded here so the Zig type system treats them as
// compile-time constants; verified below with a comptime assertion against
// protocol.zig.
pub const PUBLIC_KEY_LEN: usize = 2592;
pub const SECRET_KEY_LEN: usize = 4896;
pub const SIGNATURE_LEN: usize = 4627;

comptime {
    // Keep this module's constants in lockstep with protocol.zig. If they
    // ever diverge, one of the two is wrong — fail loudly at build time.
    const protocol = @import("protocol.zig");
    std.debug.assert(SIGNATURE_LEN == protocol.ML_DSA_87_SIGNATURE_LEN);
}

// Compile-time gate: the externs exist only for native targets that link the
// vendored liboqs. wasm32-freestanding builds this module with `enabled = false`
// and exposes compile errors if something tries to call sign/verify there.
pub const enabled = builtin.target.os.tag != .freestanding;

// ---------------------------------------------------------------------------
// liboqs externs — pqcrystals_ml_dsa_87_ref_*
// ---------------------------------------------------------------------------

extern fn pqcrystals_ml_dsa_87_ref_keypair(pk: [*]u8, sk: [*]u8) callconv(.c) c_int;

extern fn pqcrystals_ml_dsa_87_ref_signature(
    sig: [*]u8,
    siglen: *usize,
    m: [*]const u8,
    mlen: usize,
    ctx: ?[*]const u8,
    ctxlen: usize,
    sk: [*]const u8,
) callconv(.c) c_int;

extern fn pqcrystals_ml_dsa_87_ref_verify(
    sig: [*]const u8,
    siglen: usize,
    m: [*]const u8,
    mlen: usize,
    ctx: ?[*]const u8,
    ctxlen: usize,
    pk: [*]const u8,
) callconv(.c) c_int;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub const Error = error{
    /// liboqs returned a non-zero status from keypair/sign/verify.
    CryptoFailure,
    /// verify() rejected the signature.
    SignatureVerificationFailed,
    /// Build target doesn't have liboqs linked (e.g. wasm32-freestanding).
    Unavailable,
};

pub const Keypair = struct {
    public: [PUBLIC_KEY_LEN]u8,
    secret: [SECRET_KEY_LEN]u8,
};

pub fn keypair() Error!Keypair {
    if (!enabled) return error.Unavailable;
    var kp: Keypair = undefined;
    const rc = pqcrystals_ml_dsa_87_ref_keypair(&kp.public, &kp.secret);
    if (rc != 0) return error.CryptoFailure;
    return kp;
}

/// Sign `message` with `secret`. Writes the signature into `sig_out` and
/// returns the actual length (ML-DSA signatures are variable-length up to
/// SIGNATURE_LEN).
pub fn sign(
    sig_out: *[SIGNATURE_LEN]u8,
    message: []const u8,
    secret: *const [SECRET_KEY_LEN]u8,
) Error!usize {
    if (!enabled) return error.Unavailable;
    var siglen: usize = SIGNATURE_LEN;
    const rc = pqcrystals_ml_dsa_87_ref_signature(
        sig_out,
        &siglen,
        message.ptr,
        message.len,
        null,
        0,
        secret,
    );
    if (rc != 0) return error.CryptoFailure;
    return siglen;
}

/// Allocator-flavoured sign: returns an owned slice trimmed to the actual
/// signature length.
pub fn signAlloc(
    allocator: std.mem.Allocator,
    message: []const u8,
    secret: *const [SECRET_KEY_LEN]u8,
) ![]u8 {
    if (!enabled) return error.Unavailable;
    const buf = try allocator.alloc(u8, SIGNATURE_LEN);
    errdefer allocator.free(buf);
    var siglen: usize = SIGNATURE_LEN;
    const rc = pqcrystals_ml_dsa_87_ref_signature(
        buf.ptr,
        &siglen,
        message.ptr,
        message.len,
        null,
        0,
        secret,
    );
    if (rc != 0) return error.CryptoFailure;
    // ML-DSA-87's signature size is fixed at 4627 bytes in the FIPS-204
    // spec (see api.h: pqcrystals_dilithium5_BYTES). In practice the ref
    // impl always returns SIGNATURE_LEN; the trim is defensive.
    if (siglen != SIGNATURE_LEN) {
        return allocator.realloc(buf, siglen);
    }
    return buf;
}

pub fn verify(
    sig: []const u8,
    message: []const u8,
    public: *const [PUBLIC_KEY_LEN]u8,
) Error!void {
    if (!enabled) return error.Unavailable;
    const rc = pqcrystals_ml_dsa_87_ref_verify(
        sig.ptr,
        sig.len,
        message.ptr,
        message.len,
        null,
        0,
        public,
    );
    if (rc != 0) return error.SignatureVerificationFailed;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "keypair → sign → verify round-trip" {
    if (!enabled) return error.SkipZigTest;
    const kp = try keypair();
    const msg = "the jelly bean speaks with your voice";
    const sig = try signAlloc(std.testing.allocator, msg, &kp.secret);
    defer std.testing.allocator.free(sig);
    try std.testing.expectEqual(@as(usize, SIGNATURE_LEN), sig.len);
    try verify(sig, msg, &kp.public);
}

test "verify rejects tampered signature" {
    if (!enabled) return error.SkipZigTest;
    const kp = try keypair();
    const msg = "original";
    const sig = try signAlloc(std.testing.allocator, msg, &kp.secret);
    defer std.testing.allocator.free(sig);
    // Flip a bit mid-signature.
    sig[100] ^= 0x01;
    try std.testing.expectError(error.SignatureVerificationFailed, verify(sig, msg, &kp.public));
}

test "verify rejects tampered message" {
    if (!enabled) return error.SkipZigTest;
    const kp = try keypair();
    const sig = try signAlloc(std.testing.allocator, "signed message", &kp.secret);
    defer std.testing.allocator.free(sig);
    try std.testing.expectError(error.SignatureVerificationFailed, verify(sig, "tampered", &kp.public));
}

test "different keypairs produce different signatures for same message" {
    if (!enabled) return error.SkipZigTest;
    const kp1 = try keypair();
    const kp2 = try keypair();
    // ML-DSA-87 uses randomized signing by default (DILITHIUM_RANDOMIZED_SIGNING),
    // so two keys over the same message will have different sigs, and both
    // must verify under their own public key only.
    const sig1 = try signAlloc(std.testing.allocator, "msg", &kp1.secret);
    defer std.testing.allocator.free(sig1);
    const sig2 = try signAlloc(std.testing.allocator, "msg", &kp2.secret);
    defer std.testing.allocator.free(sig2);
    try std.testing.expect(!std.mem.eql(u8, sig1, sig2));
    try verify(sig1, "msg", &kp1.public);
    try verify(sig2, "msg", &kp2.public);
    try std.testing.expectError(error.SignatureVerificationFailed, verify(sig1, "msg", &kp2.public));
}
