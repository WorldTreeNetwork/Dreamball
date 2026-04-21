//! Secret-key file format for the CLI.
//!
//! Three on-disk shapes are accepted on read; only the envelope shape is written:
//!
//!   - **Envelope** (default): raw `recrypt.identity` dCBOR bytes, detected by
//!     the leading two bytes `0xd8 0xc8` (CBOR tag 200). Written by all new
//!     `jelly mint` invocations. See `src/identity_envelope.zig` for the codec
//!     and `docs/decisions/2026-04-21-identity-envelope.md` for the rationale.
//!
//!   - **Legacy ed25519-only** (64 bytes): raw Ed25519 secret key. Produced by
//!     old `jelly mint` invocations that predated ML-DSA integration. Accepted
//!     on read; callers that need ML-DSA signing must regenerate.
//!
//!   - **Legacy DJELLY hybrid** (7560 bytes, magic `DJELLY\n`): retired format.
//!     Reading returns `error.LegacyHybridKeyFileRetired`. Regenerate with
//!     `jelly mint`.

const std = @import("std");
const Allocator = std.mem.Allocator;

const protocol = @import("protocol.zig");
const signer = @import("signer.zig");
const identity_envelope = @import("identity_envelope.zig");
const fingerprint = @import("fingerprint.zig");

/// Inline `io()` — same as io.zig but we can't import io.zig here without
/// dragging it into both the `dreamball` (library) and `root` (exe) module
/// graphs, which Zig forbids (a source file may belong to only one module).
fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

const Ed25519_SECRET_LEN = 64;

pub const LoadedKeys = union(enum) {
    hybrid: signer.HybridSigningKeys,
    /// Legacy ed25519-only keys — callers that need ML-DSA signing MUST
    /// generate fresh PQ keys and rewrite the file in hybrid form.
    ed25519_only: signer.SigningKeys,
};

/// Parse a key file. Dispatches on file shape:
///   1. 64 bytes → ed25519-only legacy
///   2. leading 0xd8 0xc8 → recrypt.identity envelope (hybrid)
///   3. leading "DJELLY\n" → error.LegacyHybridKeyFileRetired
///   4. otherwise → error.BadKeyFile
pub fn decode(bytes: []const u8) !LoadedKeys {
    // Shape 1: legacy 64-byte ed25519-only
    if (bytes.len == Ed25519_SECRET_LEN) {
        var secret: [Ed25519_SECRET_LEN]u8 = undefined;
        @memcpy(&secret, bytes);
        const sk = try std.crypto.sign.Ed25519.SecretKey.fromBytes(secret);
        const kp = std.crypto.sign.Ed25519.KeyPair.fromSecretKey(sk) catch return error.BadKeyFile;
        return .{ .ed25519_only = .{
            .ed25519_secret = secret,
            .ed25519_public = kp.public_key.toBytes(),
        } };
    }

    // Shape 2: recrypt.identity envelope (tag 200 = 0xd8 0xc8)
    if (bytes.len >= 2 and bytes[0] == 0xd8 and bytes[1] == 0xc8) {
        // decode() has no allocator param; use a DebugAllocator for the
        // temporary identity parse. The HybridSigningKeys fields are all
        // fixed-size arrays copied out before identity.deinit(), so the
        // allocator lifetime doesn't escape.
        var da: std.heap.DebugAllocator(.{}) = .init;
        defer _ = da.deinit();
        return decodeEnvelope(da.allocator(), bytes);
    }

    // Shape 3: legacy DJELLY hybrid — retired
    if (bytes.len >= 7 and std.mem.eql(u8, bytes[0..7], "DJELLY\n")) {
        return error.LegacyHybridKeyFileRetired;
    }

    // Shape 4: unrecognised
    return error.BadKeyFile;
}

/// Internal: parse a recrypt.identity envelope from `bytes`, require both
/// ed25519_secret and ml_dsa.secret, return HybridSigningKeys.
fn decodeEnvelope(alloc: Allocator, bytes: []const u8) !LoadedKeys {
    var id = try identity_envelope.decode(alloc, bytes);
    defer id.deinit(alloc);

    const ed25519_secret = id.ed25519_secret orelse return error.EnvelopeMissingEd25519Secret;
    const ml = id.ml_dsa orelse return error.EnvelopeMissingMlDsaSecret;
    const ml_secret_slice = ml.secret orelse return error.EnvelopeMissingMlDsaSecret;

    if (ml.public.len != protocol.ML_DSA_87_PUBLIC_KEY_LEN) return error.BadKeyFile;
    if (ml_secret_slice.len != protocol.ML_DSA_87_SECRET_KEY_LEN) return error.BadKeyFile;

    var keys: signer.HybridSigningKeys = undefined;

    // ed25519_secret is a 32-byte seed; recover the full 64-byte secret + public
    // via the standard Ed25519 key expansion.
    const sk = try std.crypto.sign.Ed25519.SecretKey.fromBytes(ed25519_secret ++ id.ed25519_public);
    const kp = std.crypto.sign.Ed25519.KeyPair.fromSecretKey(sk) catch return error.BadKeyFile;
    keys.ed25519_public = kp.public_key.toBytes();
    // Store the 64-byte form (seed || public) that the rest of the codebase expects.
    keys.ed25519_secret = sk.toBytes();

    @memcpy(&keys.mldsa_public, ml.public[0..protocol.ML_DSA_87_PUBLIC_KEY_LEN]);
    @memcpy(&keys.mldsa_secret, ml_secret_slice[0..protocol.ML_DSA_87_SECRET_KEY_LEN]);

    return .{ .hybrid = keys };
}

pub fn readFromPath(gpa: Allocator, path: []const u8) !LoadedKeys {
    const bytes = try readAllOwned(gpa, path);
    defer gpa.free(bytes);
    // For envelope-shape files we need an allocator inside decode; pass gpa
    // via the explicit envelope path to avoid the internal GPA allocation.
    if (bytes.len >= 2 and bytes[0] == 0xd8 and bytes[1] == 0xc8) {
        return decodeEnvelope(gpa, bytes);
    }
    return decode(bytes);
}

/// Write `keys` as a `recrypt.identity` envelope to `path`.
/// `created` is the Unix epoch timestamp to embed; use `writeHybridToPath`
/// for the wall-clock convenience wrapper.
pub fn writeHybridToPathAt(
    gpa: Allocator,
    path: []const u8,
    keys: signer.HybridSigningKeys,
    created: u64,
) !void {
    // ed25519_secret is 64 bytes (seed || public); the envelope stores the
    // 32-byte seed (first half) as "ed25519-secret".
    const seed: [32]u8 = keys.ed25519_secret[0..32].*;

    const fp = fingerprint.Fingerprint.fromEd25519(keys.ed25519_public);

    const id = identity_envelope.Identity{
        .fingerprint = fp.bytes,
        .ed25519_public = keys.ed25519_public,
        .ed25519_secret = seed,
        .ml_dsa = .{
            .public = &keys.mldsa_public,
            .secret = &keys.mldsa_secret,
        },
        .name = null,
        .created = created,
        .pre = null,
        .unknown_assertions = &.{},
    };

    const envelope_bytes = try identity_envelope.encode(gpa, id);
    defer gpa.free(envelope_bytes);
    try writeAll(path, envelope_bytes);
}

/// Write `keys` as a `recrypt.identity` envelope to `path`, stamping the
/// current wall-clock time as the `created` field.
pub fn writeHybridToPath(gpa: Allocator, path: []const u8, keys: signer.HybridSigningKeys) !void {
    const ts = std.Io.Clock.real.now(io());
    const epoch_secs: u64 = @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
    return writeHybridToPathAt(gpa, path, keys, epoch_secs);
}

// Inline file helpers so key_file.zig stays self-contained and belongs to
// one module only (dreamball). The CLI has parallel helpers under cli/;
// duplicating the ~10 lines is cheaper than threading a shared module.
fn readAllOwned(gpa: Allocator, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io(), path, .{});
    defer file.close(io());
    const stat = try file.stat(io());
    const size: usize = @intCast(stat.size);
    const bytes = try gpa.alloc(u8, size);
    errdefer gpa.free(bytes);
    var buf: [4096]u8 = undefined;
    var r = file.reader(io(), &buf);
    try r.interface.readSliceAll(bytes);
    return bytes;
}

fn writeAll(path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io(), path, .{ .truncate = true });
    defer file.close(io());
    var buf: [4096]u8 = undefined;
    var w = file.writer(io(), &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

// ============================================================================
// Tests
// ============================================================================

test "hybrid round-trip via writeHybridToPathAt" {
    const allocator = std.testing.allocator;
    const keys = try signer.HybridSigningKeys.generate();

    // Write to a temp path
    const tmp_path = "/tmp/key_file_test_hybrid.key";
    try writeHybridToPathAt(allocator, tmp_path, keys, 1704067200);

    // Read back
    const loaded = try readFromPath(allocator, tmp_path);
    switch (loaded) {
        .hybrid => |h| {
            try std.testing.expectEqualSlices(u8, &keys.ed25519_secret, &h.ed25519_secret);
            try std.testing.expectEqualSlices(u8, &keys.ed25519_public, &h.ed25519_public);
            try std.testing.expectEqualSlices(u8, &keys.mldsa_public, &h.mldsa_public);
            try std.testing.expectEqualSlices(u8, &keys.mldsa_secret, &h.mldsa_secret);
        },
        else => return error.TestExpectedHybrid,
    }
}

test "legacy 64-byte file decodes as ed25519_only" {
    const classical = try signer.SigningKeys.generate();
    const loaded = try decode(&classical.ed25519_secret);
    switch (loaded) {
        .ed25519_only => |c| {
            try std.testing.expectEqualSlices(u8, &classical.ed25519_secret, &c.ed25519_secret);
            try std.testing.expectEqualSlices(u8, &classical.ed25519_public, &c.ed25519_public);
        },
        else => return error.TestExpectedEd25519Only,
    }
}

test "legacy DJELLY file rejected with LegacyHybridKeyFileRetired" {
    var djelly: [7560]u8 = undefined;
    @memcpy(djelly[0..7], "DJELLY\n");
    djelly[7] = 0x01; // version byte
    @memset(djelly[8..], 0);
    try std.testing.expectError(error.LegacyHybridKeyFileRetired, decode(&djelly));
}

test "garbage bytes rejected with BadKeyFile" {
    const bad = [_]u8{0xFF} ** 100;
    try std.testing.expectError(error.BadKeyFile, decode(&bad));
}

test "envelope missing ml-dsa secret rejected" {
    const allocator = std.testing.allocator;

    // Build an identity with ml_dsa.public but no ml_dsa.secret
    const kp = try signer.SigningKeys.generate();
    const fp = fingerprint.Fingerprint.fromEd25519(kp.ed25519_public);
    const ml_pub = [_]u8{0xAA} ** protocol.ML_DSA_87_PUBLIC_KEY_LEN;

    const id = identity_envelope.Identity{
        .fingerprint = fp.bytes,
        .ed25519_public = kp.ed25519_public,
        .ed25519_secret = kp.ed25519_secret[0..32].*,
        .ml_dsa = .{ .public = &ml_pub, .secret = null },
        .created = 1704067200,
        .name = null,
        .pre = null,
        .unknown_assertions = &.{},
    };

    const env_bytes = try identity_envelope.encode(allocator, id);
    defer allocator.free(env_bytes);

    try std.testing.expectError(error.EnvelopeMissingMlDsaSecret, decodeEnvelope(allocator, env_bytes));
}
