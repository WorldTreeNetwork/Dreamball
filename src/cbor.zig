//! Minimal dCBOR encoder for the DreamBall protocol.
//!
//! We implement only what the protocol needs:
//!   - unsigned integers (smallest encoding)
//!   - byte strings (major type 2)
//!   - text strings (major type 3)
//!   - arrays (major type 4)
//!   - maps (major type 5) — keys sorted per dCBOR
//!   - tags (major type 6) — for #6.1 epoch time, #6.200 envelope, #6.201 leaf
//!   - booleans / null (major type 7 simple values)
//!
//! Deterministic encoding rules (see recrypt/docs/wire-protocol.md §2.1):
//!   - smallest integer form
//!   - definite lengths only
//!   - no floats
//!   - map keys canonically sorted (shortest encoding first, then lexicographic on bytes)
//!
//! A real CBOR library (e.g. r4gus/zbor) will eventually replace this when the
//! protocol settles and we need full dCBOR compliance. For now the subset is
//! enough to make round-trip tests meaningful.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tag = struct {
    pub const epoch_time: u64 = 1;
    pub const envelope: u64 = 200;
    pub const leaf: u64 = 201;
};

pub const Writer = struct {
    buf: std.ArrayList(u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Writer {
        return .{ .buf = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *Writer) void {
        self.buf.deinit(self.allocator);
    }

    pub fn toOwned(self: *Writer) ![]u8 {
        return self.buf.toOwnedSlice(self.allocator);
    }

    fn writeHead(self: *Writer, major: u3, arg: u64) !void {
        const mt: u8 = @as(u8, major) << 5;
        if (arg < 24) {
            try self.buf.append(self.allocator, mt | @as(u8, @intCast(arg)));
        } else if (arg <= std.math.maxInt(u8)) {
            try self.buf.append(self.allocator, mt | 24);
            try self.buf.append(self.allocator, @intCast(arg));
        } else if (arg <= std.math.maxInt(u16)) {
            try self.buf.append(self.allocator, mt | 25);
            var b: [2]u8 = undefined;
            std.mem.writeInt(u16, &b, @intCast(arg), .big);
            try self.buf.appendSlice(self.allocator, &b);
        } else if (arg <= std.math.maxInt(u32)) {
            try self.buf.append(self.allocator, mt | 26);
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, @intCast(arg), .big);
            try self.buf.appendSlice(self.allocator, &b);
        } else {
            try self.buf.append(self.allocator, mt | 27);
            var b: [8]u8 = undefined;
            std.mem.writeInt(u64, &b, arg, .big);
            try self.buf.appendSlice(self.allocator, &b);
        }
    }

    pub fn writeUint(self: *Writer, v: u64) !void {
        try self.writeHead(0, v);
    }

    pub fn writeBytes(self: *Writer, bytes: []const u8) !void {
        try self.writeHead(2, bytes.len);
        try self.buf.appendSlice(self.allocator, bytes);
    }

    pub fn writeText(self: *Writer, s: []const u8) !void {
        try self.writeHead(3, s.len);
        try self.buf.appendSlice(self.allocator, s);
    }

    pub fn writeArrayHeader(self: *Writer, len: u64) !void {
        try self.writeHead(4, len);
    }

    pub fn writeMapHeader(self: *Writer, len: u64) !void {
        try self.writeHead(5, len);
    }

    pub fn writeTag(self: *Writer, tag: u64) !void {
        try self.writeHead(6, tag);
    }

    pub fn writeBool(self: *Writer, v: bool) !void {
        try self.buf.append(self.allocator, if (v) 0xF5 else 0xF4);
    }

    pub fn writeNull(self: *Writer) !void {
        try self.buf.append(self.allocator, 0xF6);
    }

    pub fn appendSlice(self: *Writer, bytes: []const u8) !void {
        try self.buf.appendSlice(self.allocator, bytes);
    }
};

/// dCBOR canonical map-key ordering: shorter canonical encodings first, then
/// lexicographic over the raw encoded key bytes.
pub fn compareEncodedKeys(_: void, a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return a.len < b.len;
    return std.mem.lessThan(u8, a, b);
}

pub const ReadError = error{
    Truncated,
    UnsupportedType,
};

pub const Reader = struct {
    bytes: []const u8,
    cursor: usize = 0,

    pub fn init(bytes: []const u8) Reader {
        return .{ .bytes = bytes };
    }

    fn peek(self: *const Reader) !u8 {
        if (self.cursor >= self.bytes.len) return ReadError.Truncated;
        return self.bytes[self.cursor];
    }

    fn takeByte(self: *Reader) !u8 {
        const b = try self.peek();
        self.cursor += 1;
        return b;
    }

    fn readArg(self: *Reader, info: u5) !u64 {
        if (info < 24) return info;
        return switch (info) {
            24 => @as(u64, try self.takeByte()),
            25 => blk: {
                if (self.cursor + 2 > self.bytes.len) return ReadError.Truncated;
                const v = std.mem.readInt(u16, self.bytes[self.cursor..][0..2], .big);
                self.cursor += 2;
                break :blk @as(u64, v);
            },
            26 => blk: {
                if (self.cursor + 4 > self.bytes.len) return ReadError.Truncated;
                const v = std.mem.readInt(u32, self.bytes[self.cursor..][0..4], .big);
                self.cursor += 4;
                break :blk @as(u64, v);
            },
            27 => blk: {
                if (self.cursor + 8 > self.bytes.len) return ReadError.Truncated;
                const v = std.mem.readInt(u64, self.bytes[self.cursor..][0..8], .big);
                self.cursor += 8;
                break :blk v;
            },
            else => ReadError.UnsupportedType,
        };
    }

    pub const Head = struct { major: u3, arg: u64 };

    pub fn readHead(self: *Reader) !Head {
        const b = try self.takeByte();
        const major: u3 = @intCast(b >> 5);
        const info: u5 = @intCast(b & 0x1F);
        const arg = try self.readArg(info);
        return .{ .major = major, .arg = arg };
    }

    pub fn readUint(self: *Reader) !u64 {
        const h = try self.readHead();
        if (h.major != 0) return ReadError.UnsupportedType;
        return h.arg;
    }

    pub fn readText(self: *Reader) ![]const u8 {
        const h = try self.readHead();
        if (h.major != 3) return ReadError.UnsupportedType;
        const len: usize = @intCast(h.arg);
        if (self.cursor + len > self.bytes.len) return ReadError.Truncated;
        const s = self.bytes[self.cursor .. self.cursor + len];
        self.cursor += len;
        return s;
    }

    pub fn readBytes(self: *Reader) ![]const u8 {
        const h = try self.readHead();
        if (h.major != 2) return ReadError.UnsupportedType;
        const len: usize = @intCast(h.arg);
        if (self.cursor + len > self.bytes.len) return ReadError.Truncated;
        const s = self.bytes[self.cursor .. self.cursor + len];
        self.cursor += len;
        return s;
    }

    pub fn expectTag(self: *Reader, expected: u64) !void {
        const h = try self.readHead();
        if (h.major != 6 or h.arg != expected) return ReadError.UnsupportedType;
    }

    pub fn readMapHeader(self: *Reader) !u64 {
        const h = try self.readHead();
        if (h.major != 5) return ReadError.UnsupportedType;
        return h.arg;
    }
};

test "uint smallest-form encoding" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeUint(0);
    try w.writeUint(23);
    try w.writeUint(24);
    try w.writeUint(255);
    try w.writeUint(256);
    const out = w.buf.items;
    // 0 → 0x00; 23 → 0x17; 24 → 0x18 0x18; 255 → 0x18 0xFF; 256 → 0x19 0x01 0x00
    try testing.expectEqualSlices(u8, &.{ 0x00, 0x17, 0x18, 0x18, 0x18, 0xFF, 0x19, 0x01, 0x00 }, out);
}

test "text and bytes" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeText("hi");
    try w.writeBytes(&[_]u8{ 0xDE, 0xAD });
    // text("hi") = 0x62 0x68 0x69; bytes(2) = 0x42 0xDE 0xAD
    try testing.expectEqualSlices(u8, &.{ 0x62, 'h', 'i', 0x42, 0xDE, 0xAD }, w.buf.items);
}

test "map keys sorted canonically" {
    const testing = std.testing;
    const keys = [_][]const u8{
        &[_]u8{0x62} ++ "bb", // text "bb" (3 bytes)
        &[_]u8{0x61} ++ "a", // text "a" (2 bytes)
        &[_]u8{0x62} ++ "aa", // text "aa" (3 bytes)
    };
    var sorted = [_][]const u8{ keys[0], keys[1], keys[2] };
    std.mem.sort([]const u8, &sorted, {}, compareEncodedKeys);
    // shortest first ("a"), then "aa" before "bb" lexicographically
    try testing.expectEqualSlices(u8, keys[1], sorted[0]);
    try testing.expectEqualSlices(u8, keys[2], sorted[1]);
    try testing.expectEqualSlices(u8, keys[0], sorted[2]);
}
