//! Ed25519 sign + verify via std.crypto. ML-DSA-87 sign + verify via the
//! vendored liboqs binding in `ml_dsa.zig`. The `mlDsaPlaceholder` helper
//! below is kept for paths that do not yet opt into real PQ signing (WASM
//! today, future non-CLI entry points).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;

const protocol = @import("protocol.zig");
const envelope = @import("envelope.zig");
const ml_dsa = @import("ml_dsa.zig");

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

/// A hybrid classical + post-quantum identity. CLI `mint` generates one of
/// these and stores both secrets in the `.key` file (see
/// `src/key_file.zig`). All other write-op CLIs read both secrets so every
/// re-signing attaches both Ed25519 and ML-DSA-87 `'signed'` attributes.
pub const HybridSigningKeys = struct {
    ed25519_secret: [Ed25519.SecretKey.encoded_length]u8,
    ed25519_public: [Ed25519.PublicKey.encoded_length]u8,
    mldsa_public: [protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8,
    mldsa_secret: [protocol.ML_DSA_87_SECRET_KEY_LEN]u8,

    pub fn generate() !HybridSigningKeys {
        const ed = try SigningKeys.generate();
        const pq = try ml_dsa.keypair();
        return .{
            .ed25519_secret = ed.ed25519_secret,
            .ed25519_public = ed.ed25519_public,
            .mldsa_public = pq.public,
            .mldsa_secret = pq.secret,
        };
    }

    pub fn classical(self: HybridSigningKeys) SigningKeys {
        return .{
            .ed25519_secret = self.ed25519_secret,
            .ed25519_public = self.ed25519_public,
        };
    }
};

/// Sign `unsigned_bytes` with `keys.ed25519_secret` and return the raw
/// 64-byte signature. Pairs with `ed25519SignatureBytes(keys)` so callers
/// can attach the signature to a node without managing key-pair
/// reconstruction in each CLI.
pub fn signEd25519(unsigned_bytes: []const u8, keys: SigningKeys) ![Ed25519.Signature.encoded_length]u8 {
    const kp = try keys.keyPair();
    const sig = try kp.sign(unsigned_bytes, null);
    return sig.toBytes();
}

/// Sign `unsigned_bytes` with the ML-DSA-87 secret from `keys`. Returns a
/// caller-owned slice of exactly `ML_DSA_87_SIGNATURE_LEN` bytes.
pub fn signMlDsa(allocator: Allocator, unsigned_bytes: []const u8, keys: HybridSigningKeys) ![]u8 {
    return try ml_dsa.signAlloc(allocator, unsigned_bytes, &keys.mldsa_secret);
}

/// Verify an ML-DSA-87 signature against a public key. Error on failure so
/// callers can `try` without match-on-status.
pub fn verifyMlDsa(sig: []const u8, message: []const u8, pub_key: *const [protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8) !void {
    try ml_dsa.verify(sig, message, pub_key);
}

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

test "hybrid keys mint → encode → sign → decode → verify round-trip" {
    if (!ml_dsa.enabled) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const keys = try HybridSigningKeys.generate();
    var db = protocol.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .identity_pq = keys.mldsa_public,
        .genesis_hash = [_]u8{0x11} ** 32,
        .revision = 0,
    };

    // 1. Encode unsigned, sign both, re-encode, round-trip decode.
    const unsigned = try envelope.encodeDreamBall(allocator, db);
    defer allocator.free(unsigned);

    const ed_sig = try signEd25519(unsigned, keys.classical());
    const mldsa_sig = try signMlDsa(allocator, unsigned, keys);
    defer allocator.free(mldsa_sig);

    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = mldsa_sig },
    };
    db.signatures = &sigs;
    const signed = try envelope.encodeDreamBall(allocator, db);
    defer allocator.free(signed);

    // 2. Decode core — identity_pq must round-trip.
    const decoded = try envelope.decodeDreamBallSubject(signed);
    try std.testing.expect(decoded.identity_pq != null);
    try std.testing.expectEqualSlices(u8, &keys.mldsa_public, &decoded.identity_pq.?);

    // 3. Strip signatures and verify both against their pubkeys.
    var stripped = try envelope.stripSignatures(allocator, signed);
    defer stripped.deinit();
    try std.testing.expectEqual(@as(usize, 2), stripped.signatures.len);

    // Find each sig by alg and verify.
    for (stripped.signatures) |s| {
        if (std.mem.eql(u8, s.alg, "ed25519")) {
            var arr: [64]u8 = undefined;
            @memcpy(&arr, s.value);
            const e = std.crypto.sign.Ed25519.Signature.fromBytes(arr);
            const pk = try std.crypto.sign.Ed25519.PublicKey.fromBytes(decoded.identity);
            try e.verify(stripped.unsigned, pk);
        } else if (std.mem.eql(u8, s.alg, "ml-dsa-87")) {
            try verifyMlDsa(s.value, stripped.unsigned, &decoded.identity_pq.?);
        }
    }
}

test "tampered envelope fails ML-DSA verify" {
    if (!ml_dsa.enabled) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const keys = try HybridSigningKeys.generate();
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .identity_pq = keys.mldsa_public,
        .genesis_hash = [_]u8{0x33} ** 32,
        .revision = 0,
    };

    const unsigned = try envelope.encodeDreamBall(allocator, db);
    defer allocator.free(unsigned);

    const sig = try signMlDsa(allocator, unsigned, keys);
    defer allocator.free(sig);

    // Flip a byte in the message; verify must reject.
    var tampered = try allocator.dupe(u8, unsigned);
    defer allocator.free(tampered);
    tampered[tampered.len / 2] ^= 0x01;

    try std.testing.expectError(
        error.SignatureVerificationFailed,
        verifyMlDsa(sig, tampered, &keys.mldsa_public),
    );
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
