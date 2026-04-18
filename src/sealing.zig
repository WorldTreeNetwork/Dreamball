//! DragonBall sealing: magic-prefixed file wrapper around an envelope.
//! See docs/PROTOCOL.md §5.3.
//!
//! Compression (zstd) and encryption (recrypt KEM) are stubbed with flags so
//! the framing is correct even before the dependencies are wired.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MAGIC: [4]u8 = .{ 'J', 'E', 'L', 'Y' };
pub const VERSION: u8 = 1;

pub const Flags = packed struct(u8) {
    compressed: bool = false,
    encrypted: bool = false,
    attachments_encrypted: bool = false,
    _reserved: u5 = 0,
};

pub const SealType = enum(u8) {
    plain = 0,
    recrypt_wrapped = 1,
};

pub const Attachment = struct {
    bytes: []const u8,
};

/// Write a DragonBall file body. `envelope_bytes` is already whatever the
/// flags say — if `flags.compressed`, it must already be zstd-compressed;
/// if `flags.encrypted`, it must already be recrypt-wrapped.
pub fn writeSealedFile(
    allocator: Allocator,
    envelope_bytes: []const u8,
    flags: Flags,
    seal_type: SealType,
    attachments: []const Attachment,
) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, &MAGIC);
    try buf.append(allocator, VERSION);
    try buf.append(allocator, @bitCast(flags));
    try buf.append(allocator, @intFromEnum(seal_type));
    try buf.append(allocator, 0); // reserved

    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @intCast(envelope_bytes.len), .little);
    try buf.appendSlice(allocator, &len_buf);
    try buf.appendSlice(allocator, envelope_bytes);

    var count_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &count_buf, @intCast(attachments.len), .little);
    try buf.appendSlice(allocator, &count_buf);

    for (attachments) |a| {
        std.mem.writeInt(u32, &len_buf, @intCast(a.bytes.len), .little);
        try buf.appendSlice(allocator, &len_buf);
        try buf.appendSlice(allocator, a.bytes);
    }

    return buf.toOwnedSlice(allocator);
}

pub const ParsedSeal = struct {
    flags: Flags,
    seal_type: SealType,
    envelope: []const u8,
    attachments: [][]const u8,

    pub fn deinit(self: *ParsedSeal, allocator: Allocator) void {
        allocator.free(self.attachments);
        self.* = undefined;
    }
};

pub const ParseError = error{
    BadMagic,
    UnsupportedVersion,
    UnknownSealType,
    Truncated,
    OutOfMemory,
};

pub fn readSealedFile(allocator: Allocator, bytes: []const u8) ParseError!ParsedSeal {
    if (bytes.len < 12) return ParseError.Truncated;
    if (!std.mem.eql(u8, bytes[0..4], &MAGIC)) return ParseError.BadMagic;
    if (bytes[4] != VERSION) return ParseError.UnsupportedVersion;

    const flags: Flags = @bitCast(bytes[5]);
    const seal_raw = bytes[6];
    const seal_type: SealType = switch (seal_raw) {
        0 => .plain,
        1 => .recrypt_wrapped,
        else => return ParseError.UnknownSealType,
    };

    var cursor: usize = 8;
    if (cursor + 4 > bytes.len) return ParseError.Truncated;
    const env_len = std.mem.readInt(u32, bytes[cursor..][0..4], .little);
    cursor += 4;
    if (cursor + env_len > bytes.len) return ParseError.Truncated;
    const envelope = bytes[cursor .. cursor + env_len];
    cursor += env_len;

    if (cursor + 2 > bytes.len) return ParseError.Truncated;
    const att_count = std.mem.readInt(u16, bytes[cursor..][0..2], .little);
    cursor += 2;

    var atts = try allocator.alloc([]const u8, att_count);
    errdefer allocator.free(atts);

    var i: usize = 0;
    while (i < att_count) : (i += 1) {
        if (cursor + 4 > bytes.len) return ParseError.Truncated;
        const a_len = std.mem.readInt(u32, bytes[cursor..][0..4], .little);
        cursor += 4;
        if (cursor + a_len > bytes.len) return ParseError.Truncated;
        atts[i] = bytes[cursor .. cursor + a_len];
        cursor += a_len;
    }

    return .{
        .flags = flags,
        .seal_type = seal_type,
        .envelope = envelope,
        .attachments = atts,
    };
}

test "seal round-trip with no attachments" {
    const testing = std.testing;
    const env = "ENVELOPE-BYTES";
    const sealed = try writeSealedFile(testing.allocator, env, .{}, .plain, &.{});
    defer testing.allocator.free(sealed);

    var parsed = try readSealedFile(testing.allocator, sealed);
    defer parsed.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, env, parsed.envelope);
    try testing.expectEqual(@as(usize, 0), parsed.attachments.len);
    try testing.expectEqual(SealType.plain, parsed.seal_type);
}

test "seal round-trip with attachments" {
    const testing = std.testing;
    const env = "E";
    const a1 = "attach-one";
    const a2 = "attach-two-is-longer";
    const atts = [_]Attachment{ .{ .bytes = a1 }, .{ .bytes = a2 } };
    const sealed = try writeSealedFile(
        testing.allocator,
        env,
        .{ .compressed = true },
        .recrypt_wrapped,
        &atts,
    );
    defer testing.allocator.free(sealed);

    var parsed = try readSealedFile(testing.allocator, sealed);
    defer parsed.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, env, parsed.envelope);
    try testing.expectEqual(@as(usize, 2), parsed.attachments.len);
    try testing.expectEqualSlices(u8, a1, parsed.attachments[0]);
    try testing.expectEqualSlices(u8, a2, parsed.attachments[1]);
    try testing.expect(parsed.flags.compressed);
    try testing.expectEqual(SealType.recrypt_wrapped, parsed.seal_type);
}

test "readSealedFile rejects bad magic" {
    const testing = std.testing;
    const bad = "XXXX\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00";
    try testing.expectError(ParseError.BadMagic, readSealedFile(testing.allocator, bad));
}
