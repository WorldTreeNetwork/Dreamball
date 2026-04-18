//! Ed25519 sign + verify via std.crypto.
//! ML-DSA-87 is stubbed — will arrive via a liboqs binding (or pure-Zig port)
//! in a later sprint.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;

const protocol = @import("protocol.zig");
const envelope = @import("envelope.zig");

pub const SigningKeys = struct {
    ed25519_secret: [Ed25519.SecretKey.encoded_length]u8,
    ed25519_public: [Ed25519.PublicKey.encoded_length]u8,

    pub fn generate() !SigningKeys {
        var seed: [Ed25519.KeyPair.seed_length]u8 = undefined;
        const io = std.Io.Threaded.global_single_threaded.io();
        std.Io.random(io, &seed);
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);
        return .{
            .ed25519_secret = kp.secret_key.toBytes(),
            .ed25519_public = kp.public_key.toBytes(),
        };
    }

    pub fn keyPair(self: SigningKeys) !Ed25519.KeyPair {
        const sk = try Ed25519.SecretKey.fromBytes(self.ed25519_secret);
        return Ed25519.KeyPair.fromSecretKey(sk);
    }
};

/// Returns a newly-allocated zero-filled buffer of the correct ML-DSA-87
/// signature length. Used as a placeholder until the liboqs binding lands —
/// `DreamBall.isFullySigned()` only accepts it when the env flag is set.
pub fn mlDsaPlaceholder(allocator: Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, protocol.ML_DSA_87_SIGNATURE_LEN);
    @memset(buf, 0);
    return buf;
}

pub fn isPlaceholderMldsa(sig: []const u8) bool {
    if (sig.len != protocol.ML_DSA_87_SIGNATURE_LEN) return false;
    for (sig) |b| if (b != 0) return false;
    return true;
}

/// Sign `db` with `keys`. Returns a new DreamBall with Ed25519 signature
/// appended. The caller owns the returned signature slice; we allocate it
/// here so the returned struct is self-contained for test purposes.
pub fn signDreamBall(
    allocator: Allocator,
    db: protocol.DreamBall,
    keys: SigningKeys,
) !SignedDreamBall {
    // Identity in the envelope MUST match the signing key.
    if (!std.mem.eql(u8, &db.identity, &keys.ed25519_public)) {
        return error.IdentityMismatch;
    }

    const msg = try envelope.encodeDreamBall(allocator, db);
    errdefer allocator.free(msg);

    const kp = try keys.keyPair();
    const sig = try kp.sign(msg, null);
    const sig_bytes = try allocator.alloc(u8, Ed25519.Signature.encoded_length);
    @memcpy(sig_bytes, &sig.toBytes());

    return .{
        .dreamball = db,
        .signed_bytes = msg,
        .signature = sig_bytes,
    };
}

pub const SignedDreamBall = struct {
    dreamball: protocol.DreamBall,
    /// The canonical envelope bytes that were signed.
    signed_bytes: []u8,
    /// Ed25519 signature over `signed_bytes`.
    signature: []u8,

    pub fn deinit(self: *SignedDreamBall, allocator: Allocator) void {
        allocator.free(self.signed_bytes);
        allocator.free(self.signature);
        self.* = undefined;
    }

    pub fn verify(self: SignedDreamBall) !void {
        const pk = try Ed25519.PublicKey.fromBytes(self.dreamball.identity);
        var sig_arr: [Ed25519.Signature.encoded_length]u8 = undefined;
        @memcpy(&sig_arr, self.signature);
        const sig = Ed25519.Signature.fromBytes(sig_arr);
        try sig.verify(self.signed_bytes, pk);
    }
};

test "Ed25519 sign + verify round-trip" {
    const allocator = std.testing.allocator;
    const keys = try SigningKeys.generate();
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .genesis_hash = [_]u8{0x42} ** 32,
        .revision = 0,
    };
    var signed = try signDreamBall(allocator, db, keys);
    defer signed.deinit(allocator);
    try signed.verify();
}

test "verify fails on tampered bytes" {
    const allocator = std.testing.allocator;
    const keys = try SigningKeys.generate();
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .genesis_hash = [_]u8{0x42} ** 32,
        .revision = 0,
    };
    var signed = try signDreamBall(allocator, db, keys);
    defer signed.deinit(allocator);
    // Flip a bit in the signed bytes.
    signed.signed_bytes[signed.signed_bytes.len - 1] ^= 0x01;
    try std.testing.expectError(error.SignatureVerificationFailed, signed.verify());
}

test "mlDsaPlaceholder is zero-filled + detected" {
    const allocator = std.testing.allocator;
    const buf = try mlDsaPlaceholder(allocator);
    defer allocator.free(buf);
    try std.testing.expectEqual(protocol.ML_DSA_87_SIGNATURE_LEN, buf.len);
    try std.testing.expect(isPlaceholderMldsa(buf));
    var non_zero: [protocol.ML_DSA_87_SIGNATURE_LEN]u8 = [_]u8{0} ** protocol.ML_DSA_87_SIGNATURE_LEN;
    non_zero[100] = 1;
    try std.testing.expect(!isPlaceholderMldsa(&non_zero));
}

test "identity mismatch rejected" {
    const allocator = std.testing.allocator;
    const k1 = try SigningKeys.generate();
    const k2 = try SigningKeys.generate();
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = k1.ed25519_public,
        .genesis_hash = [_]u8{0} ** 32,
        .revision = 0,
    };
    try std.testing.expectError(error.IdentityMismatch, signDreamBall(allocator, db, k2));
}
