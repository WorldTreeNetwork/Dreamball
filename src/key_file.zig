//! Secret-key file format for the CLI.
//!
//! On-disk shape: raw `recrypt.identity` dCBOR bytes (leading tag 200 =
//! `0xd8 0xc8`). Written by every `jelly mint` invocation. See
//! `src/identity_envelope.zig` for the codec and
//! `docs/decisions/2026-04-21-identity-envelope.md` for the rationale.
//!
//! There is no legacy format support. Dreamball is pre-release; any older
//! `.key` files from development are regenerated with a fresh `jelly mint`.

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

/// Parse a `recrypt.identity` envelope from `bytes`. Requires both the
/// ed25519 secret and the ML-DSA-87 secret to be present in the envelope;
/// this is Dreamball's hybrid-signing contract.
pub fn decode(gpa: Allocator, bytes: []const u8) !signer.HybridSigningKeys {
    if (bytes.len < 2 or bytes[0] != 0xd8 or bytes[1] != 0xc8) return error.BadKeyFile;

    var id = try identity_envelope.decode(gpa, bytes);
    defer id.deinit(gpa);

    const ed25519_secret = id.ed25519_secret orelse return error.EnvelopeMissingEd25519Secret;
    const ml = id.ml_dsa orelse return error.EnvelopeMissingMlDsaSecret;
    const ml_secret_slice = ml.secret orelse return error.EnvelopeMissingMlDsaSecret;

    if (ml.public.len != protocol.ML_DSA_87_PUBLIC_KEY_LEN) return error.BadKeyFile;
    if (ml_secret_slice.len != protocol.ML_DSA_87_SECRET_KEY_LEN) return error.BadKeyFile;

    var keys: signer.HybridSigningKeys = undefined;

    // `ed25519_secret` in the envelope is the 32-byte seed. Expand to the
    // 64-byte (seed || public) form that the rest of the codebase expects.
    const sk = try std.crypto.sign.Ed25519.SecretKey.fromBytes(ed25519_secret ++ id.ed25519_public);
    const kp = std.crypto.sign.Ed25519.KeyPair.fromSecretKey(sk) catch return error.BadKeyFile;
    keys.ed25519_public = kp.public_key.toBytes();
    keys.ed25519_secret = sk.toBytes();

    @memcpy(&keys.mldsa_public, ml.public[0..protocol.ML_DSA_87_PUBLIC_KEY_LEN]);
    @memcpy(&keys.mldsa_secret, ml_secret_slice[0..protocol.ML_DSA_87_SECRET_KEY_LEN]);

    return keys;
}

pub fn readFromPath(gpa: Allocator, path: []const u8) !signer.HybridSigningKeys {
    const bytes = try readAllOwned(gpa, path);
    defer gpa.free(bytes);
    return decode(gpa, bytes);
}

/// Write `keys` as a `recrypt.identity` envelope to `path`, using `created`
/// as the embedded timestamp. Use `writeHybridToPath` for the wall-clock
/// wrapper.
pub fn writeHybridToPathAt(
    gpa: Allocator,
    path: []const u8,
    keys: signer.HybridSigningKeys,
    created: u64,
) !void {
    // `ed25519_secret` is the 64-byte (seed || public) form; the envelope
    // stores the 32-byte seed as `ed25519-secret`.
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

test "envelope round-trip via writeHybridToPathAt" {
    const allocator = std.testing.allocator;
    const keys = try signer.HybridSigningKeys.generate();

    const tmp_path = "/tmp/key_file_test_hybrid.key";
    try writeHybridToPathAt(allocator, tmp_path, keys, 1704067200);

    const loaded = try readFromPath(allocator, tmp_path);
    try std.testing.expectEqualSlices(u8, &keys.ed25519_secret, &loaded.ed25519_secret);
    try std.testing.expectEqualSlices(u8, &keys.ed25519_public, &loaded.ed25519_public);
    try std.testing.expectEqualSlices(u8, &keys.mldsa_public, &loaded.mldsa_public);
    try std.testing.expectEqualSlices(u8, &keys.mldsa_secret, &loaded.mldsa_secret);
}

test "garbage bytes rejected with BadKeyFile" {
    const allocator = std.testing.allocator;
    const bad = [_]u8{0xFF} ** 100;
    try std.testing.expectError(error.BadKeyFile, decode(allocator, &bad));
}

test "short buffer rejected with BadKeyFile" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.BadKeyFile, decode(allocator, &[_]u8{0xd8}));
    try std.testing.expectError(error.BadKeyFile, decode(allocator, &[_]u8{}));
}

test "envelope missing ml-dsa secret rejected" {
    const allocator = std.testing.allocator;

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

    try std.testing.expectError(error.EnvelopeMissingMlDsaSecret, decode(allocator, env_bytes));
}

test "envelope missing ed25519 secret rejected" {
    const allocator = std.testing.allocator;

    const kp = try signer.SigningKeys.generate();
    const fp = fingerprint.Fingerprint.fromEd25519(kp.ed25519_public);
    const ml_pub = [_]u8{0xAA} ** protocol.ML_DSA_87_PUBLIC_KEY_LEN;
    const ml_sec = [_]u8{0xBB} ** protocol.ML_DSA_87_SECRET_KEY_LEN;

    const id = identity_envelope.Identity{
        .fingerprint = fp.bytes,
        .ed25519_public = kp.ed25519_public,
        .ed25519_secret = null,
        .ml_dsa = .{ .public = &ml_pub, .secret = &ml_sec },
        .created = 1704067200,
        .name = null,
        .pre = null,
        .unknown_assertions = &.{},
    };

    const env_bytes = try identity_envelope.encode(allocator, id);
    defer allocator.free(env_bytes);

    try std.testing.expectError(error.EnvelopeMissingEd25519Secret, decode(allocator, env_bytes));
}
