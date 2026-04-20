//! Secret-key file format for the CLI.
//!
//! Two on-disk shapes are accepted:
//!
//!   - **Legacy** (64 bytes total): raw Ed25519 secret key. Produced by
//!     older `jelly mint` invocations that predated ML-DSA integration.
//!     Readable but not re-signable with a PQ signature.
//!
//!   - **Hybrid** (7560 bytes total):
//!         [0..7]    magic    = "DJELLY\n"
//!         [7..8]    version  = 0x01
//!         [8..72]   Ed25519 secret (64 bytes)
//!         [72..2664]  ML-DSA-87 public key (2592 bytes)
//!         [2664..7560] ML-DSA-87 secret key (4896 bytes)
//!
//! The magic is short and human-visible in `xxd` output; it exists mainly
//! so a legacy 64-byte file and a hybrid file are distinguishable by size
//! + prefix without needing a filename convention. A version byte lets us
//! evolve the layout later (e.g., adding a PRE keypair to match recrypt's
//! wallet identity — see docs/known-gaps.md §6).

const std = @import("std");
const Allocator = std.mem.Allocator;

const protocol = @import("protocol.zig");
const signer = @import("signer.zig");

/// Inline `io()` — same as io.zig but we can't import io.zig here without
/// dragging it into both the `dreamball` (library) and `root` (exe) module
/// graphs, which Zig forbids (a source file may belong to only one module).
fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

const Ed25519_SECRET_LEN = 64;
const MAGIC = "DJELLY\n";
const VERSION: u8 = 0x01;

pub const HYBRID_LEN: usize =
    MAGIC.len + 1 + Ed25519_SECRET_LEN +
    protocol.ML_DSA_87_PUBLIC_KEY_LEN +
    protocol.ML_DSA_87_SECRET_KEY_LEN;

pub const LoadedKeys = union(enum) {
    hybrid: signer.HybridSigningKeys,
    /// Legacy ed25519-only keys — callers that need ML-DSA signing MUST
    /// generate fresh PQ keys and rewrite the file in hybrid form.
    ed25519_only: signer.SigningKeys,
};

/// Serialize `keys` in the hybrid format (7560 bytes). Caller owns the
/// returned buffer.
pub fn encodeHybrid(allocator: Allocator, keys: signer.HybridSigningKeys) ![]u8 {
    const buf = try allocator.alloc(u8, HYBRID_LEN);
    errdefer allocator.free(buf);

    var i: usize = 0;
    @memcpy(buf[i..][0..MAGIC.len], MAGIC);
    i += MAGIC.len;
    buf[i] = VERSION;
    i += 1;
    @memcpy(buf[i..][0..Ed25519_SECRET_LEN], &keys.ed25519_secret);
    i += Ed25519_SECRET_LEN;
    @memcpy(buf[i..][0..protocol.ML_DSA_87_PUBLIC_KEY_LEN], &keys.mldsa_public);
    i += protocol.ML_DSA_87_PUBLIC_KEY_LEN;
    @memcpy(buf[i..][0..protocol.ML_DSA_87_SECRET_KEY_LEN], &keys.mldsa_secret);
    i += protocol.ML_DSA_87_SECRET_KEY_LEN;
    std.debug.assert(i == HYBRID_LEN);
    return buf;
}

/// Parse a key file. Recognises both legacy and hybrid shapes.
pub fn decode(bytes: []const u8) !LoadedKeys {
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

    if (bytes.len != HYBRID_LEN) return error.BadKeyFileLength;
    var i: usize = 0;
    if (!std.mem.eql(u8, bytes[i..][0..MAGIC.len], MAGIC)) return error.BadKeyFileMagic;
    i += MAGIC.len;
    if (bytes[i] != VERSION) return error.UnsupportedKeyFileVersion;
    i += 1;

    var keys: signer.HybridSigningKeys = undefined;
    @memcpy(&keys.ed25519_secret, bytes[i..][0..Ed25519_SECRET_LEN]);
    i += Ed25519_SECRET_LEN;

    // Recover the Ed25519 public key from the secret.
    const sk = try std.crypto.sign.Ed25519.SecretKey.fromBytes(keys.ed25519_secret);
    const kp = std.crypto.sign.Ed25519.KeyPair.fromSecretKey(sk) catch return error.BadKeyFile;
    keys.ed25519_public = kp.public_key.toBytes();

    @memcpy(&keys.mldsa_public, bytes[i..][0..protocol.ML_DSA_87_PUBLIC_KEY_LEN]);
    i += protocol.ML_DSA_87_PUBLIC_KEY_LEN;
    @memcpy(&keys.mldsa_secret, bytes[i..][0..protocol.ML_DSA_87_SECRET_KEY_LEN]);
    return .{ .hybrid = keys };
}

pub fn readFromPath(gpa: Allocator, path: []const u8) !LoadedKeys {
    const bytes = try readAllOwned(gpa, path);
    defer gpa.free(bytes);
    return decode(bytes);
}

pub fn writeHybridToPath(gpa: Allocator, path: []const u8, keys: signer.HybridSigningKeys) !void {
    const bytes = try encodeHybrid(gpa, keys);
    defer gpa.free(bytes);
    try writeAll(path, bytes);
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

test "hybrid round-trip" {
    const allocator = std.testing.allocator;
    const keys = try signer.HybridSigningKeys.generate();
    const bytes = try encodeHybrid(allocator, keys);
    defer allocator.free(bytes);
    try std.testing.expectEqual(HYBRID_LEN, bytes.len);
    const loaded = try decode(bytes);
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

test "wrong length rejected" {
    const bad = [_]u8{0} ** 123;
    try std.testing.expectError(error.BadKeyFileLength, decode(&bad));
}
