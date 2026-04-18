//! Fingerprint = Blake3(Ed25519 public key), 32 bytes. Base58 for display.

const std = @import("std");

pub const Fingerprint = struct {
    bytes: [32]u8,

    pub fn fromEd25519(pk: [32]u8) Fingerprint {
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(&pk);
        var out: [32]u8 = undefined;
        hasher.final(&out);
        return .{ .bytes = out };
    }

    pub fn eql(a: Fingerprint, b: Fingerprint) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }
};

test "fingerprint is deterministic" {
    const pk: [32]u8 = [_]u8{1} ** 32;
    const a = Fingerprint.fromEd25519(pk);
    const b = Fingerprint.fromEd25519(pk);
    try std.testing.expect(a.eql(b));
}

test "fingerprint varies with input" {
    const pk1: [32]u8 = [_]u8{1} ** 32;
    const pk2: [32]u8 = [_]u8{2} ** 32;
    const a = Fingerprint.fromEd25519(pk1);
    const b = Fingerprint.fromEd25519(pk2);
    try std.testing.expect(!a.eql(b));
}
