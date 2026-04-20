//! Golden-bytes lock — pins the canonical CBOR output of the DreamBall
//! encoder to a known Blake3 hash. Any future change that alters the
//! wire bytes must update these constants *and* be reviewed for
//! compatibility implications (version bump? breaking change?).

const std = @import("std");
const protocol = @import("protocol.zig");
const envelope = @import("envelope.zig");

/// Expected Blake3 hex hash for an all-zeros seed node:
///   stage = .seed
///   identity = [0] * 32
///   genesis_hash = [0] * 32
///   revision = 0
///   (no attributes — core only)
pub const GOLDEN_ZERO_SEED_BLAKE3: []const u8 = "df27762290f8b4dd2ac32fca17726483ecbe38b0a4ec954dd136de846f1c6998";

fn blake3Hex(bytes: []const u8) [64]u8 {
    var out: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(bytes);
    hasher.final(&out);
    var hex: [64]u8 = undefined;
    const charset = "0123456789abcdef";
    for (out, 0..) |b, i| {
        hex[i * 2] = charset[(b >> 4) & 0xF];
        hex[i * 2 + 1] = charset[b & 0xF];
    }
    return hex;
}

/// Pinned Blake3 for a canonical jelly.memory-connection envelope.
/// Core keys must emit in dCBOR order: to(2), from(4), kind(4), type(4), format-version(14).
/// If this fails, inspect writeMemoryConnection core-key ordering in envelope_v2.zig.
pub const GOLDEN_MEMORY_CONNECTION_BLAKE3: []const u8 = "d555eba7765504311b906ffdcf1c5df6bf8d3f3cb064fa205522d1c75f686255";

test "golden bytes: all-zeros seed node (core only)" {
    const allocator = std.testing.allocator;
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
        .revision = 0,
    };
    const bytes = try envelope.encodeDreamBall(allocator, db);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    // Print on mismatch so first-run generation is easy.
    std.testing.expectEqualSlices(u8, GOLDEN_ZERO_SEED_BLAKE3, &hex) catch |err| {
        std.debug.print("\n  GOLDEN MISMATCH\n  observed: {s}\n  expected: {s}\n  (update GOLDEN_ZERO_SEED_BLAKE3 in src/golden.zig if the change is intentional)\n", .{ hex, GOLDEN_ZERO_SEED_BLAKE3 });
        return err;
    };
}

test "golden bytes: jelly.memory-connection canonical ordering" {
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const m: v2.Memory = .{
        .nodes = &.{},
        .connections = &[_]v2.MemoryConnection{
            .{ .from = 1, .to = 2, .kind = .temporal, .strength = 0.5 },
        },
    };
    const bytes = try envelope_v2.encodeMemory(allocator, m);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    if (!std.mem.eql(u8, GOLDEN_MEMORY_CONNECTION_BLAKE3, "__RECOMPUTE_ON_FIRST_RUN__")) {
        std.testing.expectEqualSlices(u8, GOLDEN_MEMORY_CONNECTION_BLAKE3, &hex) catch |err| {
            std.debug.print("\n  MEMORY-CONNECTION GOLDEN MISMATCH\n  observed: {s}\n  expected: {s}\n", .{ hex, GOLDEN_MEMORY_CONNECTION_BLAKE3 });
            return err;
        };
    } else {
        // First-run sentinel: print the observed hash so we can commit it.
        std.debug.print("\n  MEMORY-CONNECTION golden first run — commit this value to GOLDEN_MEMORY_CONNECTION_BLAKE3:\n  {s}\n", .{hex});
    }
}
