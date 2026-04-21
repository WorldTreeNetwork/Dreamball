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

/// Errors returned by the dCBOR reader.
pub const Error = error{
    /// An integer (or length argument) was encoded in more bytes than needed.
    NonCanonicalInteger,
    /// Map keys are not in the required dCBOR order (shorter first, then lex).
    NonCanonicalMapOrder,
    /// Encountered an indefinite-length item, float, or other unsupported CBOR construct.
    UnsupportedCborItem,
    /// Encountered a CBOR tag other than 1, 200, or 201.
    UnknownTag,
    /// `expectTag` was called but the encoded tag value did not match.
    UnexpectedTag,
    /// The input buffer ended before the item was fully read.
    BufferTooShort,
    /// The initial byte's major type is not valid in this context.
    InvalidMajorType,
};

pub const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn init(bytes: []const u8) Reader {
        return .{ .bytes = bytes, .pos = 0 };
    }

    /// Returns the major type of the next byte without consuming it.
    pub fn peekMajor(self: *const Reader) !u3 {
        if (self.pos >= self.bytes.len) return Error.BufferTooShort;
        return @intCast(self.bytes[self.pos] >> 5);
    }

    /// Unconsumed bytes starting at current position.
    pub fn remaining(self: *const Reader) []const u8 {
        return self.bytes[self.pos..];
    }

    /// True when all bytes have been consumed.
    pub fn eof(self: *const Reader) bool {
        return self.pos >= self.bytes.len;
    }

    fn takeByte(self: *Reader) !u8 {
        if (self.pos >= self.bytes.len) return Error.BufferTooShort;
        const b = self.bytes[self.pos];
        self.pos += 1;
        return b;
    }

    /// Decode the additional-info field into a u64 argument.
    /// Enforces smallest-form: if the value could have been encoded in fewer
    /// bytes, returns `error.NonCanonicalInteger`.
    fn readArgChecked(self: *Reader, info: u5) !u64 {
        if (info < 24) {
            // Direct value: always canonical.
            return @as(u64, info);
        }
        switch (info) {
            24 => {
                const v = try self.takeByte();
                // Must be >= 24; values 0–23 fit in the initial byte.
                if (v < 24) return Error.NonCanonicalInteger;
                return @as(u64, v);
            },
            25 => {
                if (self.pos + 2 > self.bytes.len) return Error.BufferTooShort;
                const v = std.mem.readInt(u16, self.bytes[self.pos..][0..2], .big);
                self.pos += 2;
                // Must be >= 256; values 0–255 fit in the u8 form.
                if (v <= std.math.maxInt(u8)) return Error.NonCanonicalInteger;
                return @as(u64, v);
            },
            26 => {
                if (self.pos + 4 > self.bytes.len) return Error.BufferTooShort;
                const v = std.mem.readInt(u32, self.bytes[self.pos..][0..4], .big);
                self.pos += 4;
                // Must be >= 65536; values 0–65535 fit in the u16 form.
                if (v <= std.math.maxInt(u16)) return Error.NonCanonicalInteger;
                return @as(u64, v);
            },
            27 => {
                if (self.pos + 8 > self.bytes.len) return Error.BufferTooShort;
                const v = std.mem.readInt(u64, self.bytes[self.pos..][0..8], .big);
                self.pos += 8;
                // Must be >= 2^32; values 0–(2^32-1) fit in the u32 form.
                if (v <= std.math.maxInt(u32)) return Error.NonCanonicalInteger;
                return v;
            },
            // 28–30: reserved; 31: indefinite-length break code.
            else => return Error.UnsupportedCborItem,
        }
    }

    pub const Head = struct { major: u3, arg: u64 };

    /// Read and return the major type + argument, enforcing smallest-form.
    pub fn readHead(self: *Reader) !Head {
        const b = try self.takeByte();
        const major: u3 = @intCast(b >> 5);
        const info: u5 = @intCast(b & 0x1F);
        // Indefinite-length marker (info == 31) — reject it here so every
        // caller automatically rejects indefinite-length items.
        if (info == 31) return Error.UnsupportedCborItem;
        const arg = try self.readArgChecked(info);
        return .{ .major = major, .arg = arg };
    }

    /// Read an unsigned integer (major 0). Rejects non-smallest encoding.
    pub fn readUint(self: *Reader) !u64 {
        const h = try self.readHead();
        if (h.major != 0) return Error.InvalidMajorType;
        return h.arg;
    }

    /// Read a byte string (major 2). Returns a borrowed slice into `self.bytes`.
    pub fn readBytes(self: *Reader) ![]const u8 {
        const h = try self.readHead();
        if (h.major != 2) return Error.InvalidMajorType;
        const len: usize = @intCast(h.arg);
        if (self.pos + len > self.bytes.len) return Error.BufferTooShort;
        const s = self.bytes[self.pos .. self.pos + len];
        self.pos += len;
        return s;
    }

    /// Read a text string (major 3). Returns a borrowed slice. Does NOT
    /// validate UTF-8 (CBOR-level concern, not ours).
    pub fn readText(self: *Reader) ![]const u8 {
        const h = try self.readHead();
        if (h.major != 3) return Error.InvalidMajorType;
        const len: usize = @intCast(h.arg);
        if (self.pos + len > self.bytes.len) return Error.BufferTooShort;
        const s = self.bytes[self.pos .. self.pos + len];
        self.pos += len;
        return s;
    }

    /// Read an array header (major 4). Returns the item count.
    /// Rejects indefinite-length (already handled in readHead).
    pub fn readArrayHeader(self: *Reader) !u64 {
        const h = try self.readHead();
        if (h.major != 4) return Error.InvalidMajorType;
        return h.arg;
    }

    /// Read a map header (major 5). Returns the pair count.
    pub fn readMapHeader(self: *Reader) !u64 {
        const h = try self.readHead();
        if (h.major != 5) return Error.InvalidMajorType;
        return h.arg;
    }

    /// Read a tag value (major 6). Only permits tags 1, 200, and 201;
    /// any other value → `error.UnknownTag`. Does NOT consume the tagged item.
    pub fn readTag(self: *Reader) !u64 {
        const h = try self.readHead();
        if (h.major != 6) return Error.InvalidMajorType;
        const tag = h.arg;
        if (tag != Tag.epoch_time and tag != Tag.envelope and tag != Tag.leaf) {
            return Error.UnknownTag;
        }
        return tag;
    }

    /// Read a tag and assert it equals `want`. Returns `error.UnexpectedTag`
    /// on mismatch (after `readTag` validates that the tag is in the allowed set).
    pub fn expectTag(self: *Reader, want: u64) !void {
        const got = try self.readTag();
        if (got != want) return Error.UnexpectedTag;
    }

    /// Read a boolean (major 7, simple value 20=false, 21=true).
    /// Any other major-7 simple value → `error.UnsupportedCborItem`.
    pub fn readBool(self: *Reader) !bool {
        const b = try self.takeByte();
        return switch (b) {
            0xF4 => false,
            0xF5 => true,
            else => Error.UnsupportedCborItem,
        };
    }

    /// Skip over one complete CBOR data item (used internally by verifyMapKeyOrder).
    pub fn skipItem(self: *Reader) !void {
        const b = try self.takeByte();
        const major: u3 = @intCast(b >> 5);
        const info: u5 = @intCast(b & 0x1F);
        if (info == 31) return Error.UnsupportedCborItem;
        const arg = try self.readArgChecked(info);
        switch (major) {
            0, 6 => {
                // uint or tag-with-no-extra-content: arg is the value.
                // For tags we need to skip the tagged item too.
                if (major == 6) try self.skipItem();
            },
            1 => {}, // negative int: arg encodes -(arg+1), no extra bytes
            2, 3 => {
                // byte/text string: skip `arg` content bytes
                const len: usize = @intCast(arg);
                if (self.pos + len > self.bytes.len) return Error.BufferTooShort;
                self.pos += len;
            },
            4 => {
                // array: skip `arg` items
                const count: usize = @intCast(arg);
                var i: usize = 0;
                while (i < count) : (i += 1) try self.skipItem();
            },
            5 => {
                // map: skip `arg` key-value pairs
                const pairs: usize = @intCast(arg);
                var i: usize = 0;
                while (i < pairs) : (i += 1) {
                    try self.skipItem();
                    try self.skipItem();
                }
            },
            7 => {
                // simple/float — only accept the two bool values
                // (0xF4/0xF5 were already consumed as the initial byte `b`)
                if (b != 0xF4 and b != 0xF5) return Error.UnsupportedCborItem;
            },
        }
    }
};

/// Walk the CBOR map starting at `bytes[0]` and verify that each successive
/// key's CBOR-encoded form sorts strictly after the previous one, using the
/// dCBOR canonical ordering: shorter encoded form first; equal length → lex
/// over the raw encoded bytes. Returns `error.NonCanonicalMapOrder` on any
/// violation.
pub fn verifyMapKeyOrder(bytes: []const u8) !void {
    var r = Reader.init(bytes);
    const pairs = try r.readMapHeader();
    var prev_start: usize = 0;
    var prev_end: usize = 0;
    var i: usize = 0;
    while (i < pairs) : (i += 1) {
        const key_start = r.pos;
        try r.skipItem(); // skip the key
        const key_end = r.pos;
        try r.skipItem(); // skip the value

        if (i > 0) {
            const prev_key = bytes[prev_start..prev_end];
            const cur_key = bytes[key_start..key_end];
            // Keys must be strictly increasing: shorter first, then lex.
            const ok = blk: {
                if (prev_key.len != cur_key.len) break :blk prev_key.len < cur_key.len;
                break :blk std.mem.lessThan(u8, prev_key, cur_key);
            };
            if (!ok) return Error.NonCanonicalMapOrder;
        }
        prev_start = key_start;
        prev_end = key_end;
    }
}

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

// ── Reader round-trip tests ───────────────────────────────────────────────────

test "reader round-trip uint" {
    const testing = std.testing;
    const values = [_]u64{ 0, 23, 24, 255, 256, 65535, 65536, std.math.maxInt(u32), std.math.maxInt(u64) };
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    for (values) |v| try w.writeUint(v);
    var r = Reader.init(w.buf.items);
    for (values) |v| {
        const got = try r.readUint();
        try testing.expectEqual(v, got);
    }
    try testing.expect(r.eof());
}

test "reader round-trip bytes" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    const payload = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try w.writeBytes(&payload);
    var r = Reader.init(w.buf.items);
    const got = try r.readBytes();
    try testing.expectEqualSlices(u8, &payload, got);
    try testing.expect(r.eof());
}

test "reader round-trip text" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeText("hello");
    var r = Reader.init(w.buf.items);
    const got = try r.readText();
    try testing.expectEqualSlices(u8, "hello", got);
    try testing.expect(r.eof());
}

test "reader round-trip array header" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeArrayHeader(7);
    var r = Reader.init(w.buf.items);
    const n = try r.readArrayHeader();
    try testing.expectEqual(@as(u64, 7), n);
}

test "reader round-trip map header" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeMapHeader(3);
    var r = Reader.init(w.buf.items);
    const n = try r.readMapHeader();
    try testing.expectEqual(@as(u64, 3), n);
}

test "reader round-trip tag" {
    const testing = std.testing;
    // Tag 200 (envelope) followed by a uint payload.
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeTag(Tag.envelope);
    try w.writeUint(42);
    var r = Reader.init(w.buf.items);
    const t = try r.readTag();
    try testing.expectEqual(Tag.envelope, t);
    const v = try r.readUint();
    try testing.expectEqual(@as(u64, 42), v);
}

test "reader expectTag match" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeTag(Tag.leaf);
    try w.writeUint(0);
    var r = Reader.init(w.buf.items);
    try r.expectTag(Tag.leaf);
    _ = try r.readUint();
}

test "reader expectTag mismatch" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeTag(Tag.leaf);
    try w.writeUint(0);
    var r = Reader.init(w.buf.items);
    // Tag.leaf == 201, we expect 200 → UnexpectedTag
    try testing.expectError(Error.UnexpectedTag, r.expectTag(Tag.envelope));
}

test "reader round-trip bool" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeBool(true);
    try w.writeBool(false);
    var r = Reader.init(w.buf.items);
    try testing.expectEqual(true, try r.readBool());
    try testing.expectEqual(false, try r.readBool());
    try testing.expect(r.eof());
}

test "reader peekMajor" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeUint(5);
    var r = Reader.init(w.buf.items);
    const major = try r.peekMajor();
    try testing.expectEqual(@as(u3, 0), major); // major 0 = uint
    // pos must be unchanged
    try testing.expectEqual(@as(usize, 0), r.pos);
}

test "reader remaining and eof" {
    const testing = std.testing;
    const data = [_]u8{ 0x01, 0x02 };
    var r = Reader.init(&data);
    try testing.expect(!r.eof());
    try testing.expectEqual(@as(usize, 2), r.remaining().len);
    _ = try r.readUint(); // consumes 0x01
    try testing.expectEqual(@as(usize, 1), r.remaining().len);
    _ = try r.readUint(); // consumes 0x02
    try testing.expect(r.eof());
}

// ── Rejection / error-path tests ─────────────────────────────────────────────

test "reader rejects non-canonical uint" {
    const testing = std.testing;
    // 0x18 0x05 encodes value 5 in 2 bytes — non-canonical (fits in 1 byte).
    const bad = [_]u8{ 0x18, 0x05 };
    var r = Reader.init(&bad);
    try testing.expectError(Error.NonCanonicalInteger, r.readUint());
}

test "reader rejects non-canonical uint u16 form" {
    const testing = std.testing;
    // 0x19 0x00 0xFF encodes value 255 in 3 bytes — fits in 2-byte (u8) form.
    const bad = [_]u8{ 0x19, 0x00, 0xFF };
    var r = Reader.init(&bad);
    try testing.expectError(Error.NonCanonicalInteger, r.readUint());
}

test "reader rejects non-canonical uint u32 form" {
    const testing = std.testing;
    // 0x1a 0x00 0x00 0xFF 0xFF encodes 65535 — fits in u16 form.
    const bad = [_]u8{ 0x1a, 0x00, 0x00, 0xFF, 0xFF };
    var r = Reader.init(&bad);
    try testing.expectError(Error.NonCanonicalInteger, r.readUint());
}

test "reader rejects non-canonical uint u64 form" {
    const testing = std.testing;
    // 0x1b with value that fits in u32 is non-canonical.
    const bad = [_]u8{ 0x1b, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF };
    var r = Reader.init(&bad);
    try testing.expectError(Error.NonCanonicalInteger, r.readUint());
}

test "reader rejects mis-ordered map" {
    const testing = std.testing;
    // Build a 2-key map with keys "bb" then "a" — reverse of canonical order.
    // Canonical: shorter key "a" (encoded as 0x61 'a') must come before "bb"
    // (encoded as 0x62 'b' 'b'). We write them in the wrong order by hand.
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeMapHeader(2);
    try w.writeText("bb"); // longer key first — violates dCBOR ordering
    try w.writeUint(1);
    try w.writeText("a");
    try w.writeUint(2);
    try testing.expectError(Error.NonCanonicalMapOrder, verifyMapKeyOrder(w.buf.items));
}

test "reader accepts correctly-ordered map" {
    const testing = std.testing;
    var w = Writer.init(testing.allocator);
    defer w.deinit();
    try w.writeMapHeader(2);
    try w.writeText("a"); // shorter key first
    try w.writeUint(1);
    try w.writeText("bb");
    try w.writeUint(2);
    try verifyMapKeyOrder(w.buf.items); // must not error
}

test "reader rejects unknown tag" {
    const testing = std.testing;
    // Tag 42 is not in the allowed set {1, 200, 201}.
    // CBOR major 6, arg 42: 0xd8 0x2a (tag arg 42 needs 1 extra byte since 42 >= 24).
    const bad = [_]u8{ 0xd8, 0x2a, 0x00 }; // tag(42) uint(0)
    var r = Reader.init(&bad);
    try testing.expectError(Error.UnknownTag, r.readTag());
}

test "reader rejects indefinite-length array" {
    const testing = std.testing;
    // 0x9f is indefinite-length array open, 0xff is break.
    const bad = [_]u8{ 0x9f, 0x01, 0xff };
    var r = Reader.init(&bad);
    try testing.expectError(Error.UnsupportedCborItem, r.readArrayHeader());
}

test "reader rejects indefinite-length map" {
    const testing = std.testing;
    // 0xbf is indefinite-length map open.
    const bad = [_]u8{ 0xbf, 0xff };
    var r = Reader.init(&bad);
    try testing.expectError(Error.UnsupportedCborItem, r.readMapHeader());
}

test "reader rejects float f32" {
    const testing = std.testing;
    // 0xfa = major 7, additional info 26 → single-precision float.
    const bad = [_]u8{ 0xfa, 0x3f, 0x80, 0x00, 0x00 }; // 1.0f as IEEE 754
    var r = Reader.init(&bad);
    // readBool is the only major-7 reader; it accepts only 0xF4/0xF5.
    try testing.expectError(Error.UnsupportedCborItem, r.readBool());
}

test "reader rejects null as bool" {
    const testing = std.testing;
    // 0xF6 = null, not a bool
    const bad = [_]u8{0xF6};
    var r = Reader.init(&bad);
    try testing.expectError(Error.UnsupportedCborItem, r.readBool());
}
