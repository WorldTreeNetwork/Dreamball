//! dCBOR helpers for the DreamBall protocol.
//!
//! This module does **not** re-implement CBOR. CBOR encoding/decoding is
//! provided by the `zbor` library — see `zbor.builder` (write side) and
//! `zbor.DataItem` (read side). What we add here is the thin layer of
//! *determinism* required by dCBOR (see recrypt/docs/wire-protocol.md §2.1)
//! that zbor itself does not enforce:
//!
//!   - Canonical map-key ordering (shorter encoded form first, then lex).
//!   - `Pair` / `PairList` — collect pre-serialised key/value CBOR bytes,
//!     then sort and emit in canonical order.
//!   - `itemLen` — the byte-length of a single CBOR data item at `bytes[start]`.
//!     Used when a caller needs to slice an item verbatim (e.g. to preserve
//!     an unknown assertion byte-for-byte). zbor exposes `cbor.burn` /
//!     `zbor.advance`, which moves a cursor past an item; `itemLen` is the
//!     same thing, packaged to return the length directly.
//!
//! The CBOR Tag numbers DreamBall uses:
//!
//!   - `Tag.epoch_time` (1)  — standard RFC 8949 epoch-seconds tag.
//!   - `Tag.envelope`   (200) — bc-envelope outer wrapper.
//!   - `Tag.leaf`       (201) — bc-envelope leaf (subject / pred / obj).

const std = @import("std");
const Allocator = std.mem.Allocator;
const zbor = @import("zbor");

pub const Tag = struct {
    pub const epoch_time: u64 = 1;
    pub const envelope: u64 = 200;
    pub const leaf: u64 = 201;
};

// ─── Pair / PairList ────────────────────────────────────────────────────────
//
// dCBOR canonical map-key ordering: shorter canonical encodings first, then
// lexicographic over the raw encoded key bytes. Callers pre-serialise each
// key's CBOR form into `key` and the value's CBOR form into `value`, call
// `sort()`, then emit.

pub const Pair = struct { key: []const u8, value: []const u8 };

pub fn pairLt(_: void, a: Pair, b: Pair) bool {
    if (a.key.len != b.key.len) return a.key.len < b.key.len;
    return std.mem.lessThan(u8, a.key, b.key);
}

/// A growing list of pre-serialised (key, value) CBOR byte pairs that can be
/// sorted and emitted as a dCBOR canonical map. `key` stores the *pre-encoded*
/// key CBOR (usually a text string) so the length/lex comparison is exact.
/// `value` stores the pre-encoded value CBOR.
///
/// `addText`/`addUint`/`addBytes` store the key as a plain string (no CBOR
/// wrapper) because the existing envelope.zig emission path writes the key
/// via `writer.writeTextString(p.key)` at emit time — i.e. keys are always
/// text strings, and the comparison over plain-string length+lex matches the
/// comparison over CBOR-text-string length+lex for every key under 256 chars
/// (the header byte for a text string under length 24 is (0x60 | len), so
/// two text keys of equal length sort the same as their plain strings).
pub const PairList = struct {
    pairs: std.ArrayListUnmanaged(Pair) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) PairList {
        return .{ .pairs = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *PairList) void {
        for (self.pairs.items) |p| {
            self.allocator.free(p.key);
            self.allocator.free(p.value);
        }
        self.pairs.deinit(self.allocator);
    }

    pub fn addOwned(self: *PairList, key: []const u8, value: []u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        try self.pairs.append(self.allocator, .{ .key = key_copy, .value = value });
    }

    pub fn addText(self: *PairList, key: []const u8, text: []const u8) !void {
        var ai = std.Io.Writer.Allocating.init(self.allocator);
        errdefer ai.deinit();
        try zbor.builder.writeTextString(&ai.writer, text);
        const bytes = try ai.toOwnedSlice();
        try self.addOwned(key, bytes);
    }

    pub fn addUint(self: *PairList, key: []const u8, v: u64) !void {
        var ai = std.Io.Writer.Allocating.init(self.allocator);
        errdefer ai.deinit();
        try zbor.builder.writeInt(&ai.writer, @intCast(v));
        const bytes = try ai.toOwnedSlice();
        try self.addOwned(key, bytes);
    }

    pub fn addBytes(self: *PairList, key: []const u8, b: []const u8) !void {
        var ai = std.Io.Writer.Allocating.init(self.allocator);
        errdefer ai.deinit();
        try zbor.builder.writeByteString(&ai.writer, b);
        const raw = try ai.toOwnedSlice();
        try self.addOwned(key, raw);
    }

    pub fn addEpoch(self: *PairList, key: []const u8, epoch: i64) !void {
        var ai = std.Io.Writer.Allocating.init(self.allocator);
        errdefer ai.deinit();
        try zbor.builder.writeTag(&ai.writer, Tag.epoch_time);
        try zbor.builder.writeInt(&ai.writer, @intCast(epoch));
        const bytes = try ai.toOwnedSlice();
        try self.addOwned(key, bytes);
    }

    /// Consumes `inner_bytes`: the PairList takes ownership.
    pub fn addRawOwned(self: *PairList, key: []const u8, inner_bytes: []u8) !void {
        try self.addOwned(key, inner_bytes);
    }

    pub fn sort(self: *PairList) void {
        std.sort.insertion(Pair, self.pairs.items, {}, pairLt);
    }
};

// ─── itemLen ────────────────────────────────────────────────────────────────
//
// Compute the byte length of the CBOR item starting at `bytes[start]`,
// including head + nested content. Used to slice items verbatim (e.g. to
// capture unknown assertions byte-for-byte). zbor exposes the same
// operation as `zbor.advance` (alias for `cbor.burn`) which advances a
// cursor past an item — we wrap that into a length-returning form.

pub const ItemLenError = error{ Truncated, UnsupportedType };

pub fn itemLen(bytes: []const u8, start: usize) ItemLenError!usize {
    if (start >= bytes.len) return ItemLenError.Truncated;
    var cursor: usize = start;
    // `zbor.advance` returns `?void` — null on malformed input.
    if (zbor.advance(bytes, &cursor) == null) return ItemLenError.Truncated;
    if (cursor < start or cursor > bytes.len) return ItemLenError.Truncated;
    return cursor - start;
}

// ─── Small write helpers ────────────────────────────────────────────────────
//
// Every DreamBall encoder follows the same skeleton: create an allocating
// writer, emit dCBOR via `zbor.builder.*`, return the owned byte slice.
// Call sites use `zbor.builder` functions directly (see envelope.zig); these
// helpers just reduce the boilerplate for the top-level "open a writer /
// close out an owned slice" pattern.

/// Open an allocating writer whose `toOwnedSlice()` yields the finalised bytes.
/// Callers write via `zbor.builder.*` on `&ai.writer` and call
/// `try ai.toOwnedSlice()` when done.
pub inline fn openWriter(allocator: Allocator) std.Io.Writer.Allocating {
    return std.Io.Writer.Allocating.init(allocator);
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "pairLt: shorter first, then lex" {
    const p_a = Pair{ .key = "a", .value = "" };
    const p_aa = Pair{ .key = "aa", .value = "" };
    const p_bb = Pair{ .key = "bb", .value = "" };
    // shorter wins
    try std.testing.expect(pairLt({}, p_a, p_aa));
    try std.testing.expect(!pairLt({}, p_aa, p_a));
    // equal length → lex
    try std.testing.expect(pairLt({}, p_aa, p_bb));
    try std.testing.expect(!pairLt({}, p_bb, p_aa));
}

test "itemLen: uint, text, bytes, array, map, tag" {
    // Single uint "5" → 1 byte
    try std.testing.expectEqual(@as(usize, 1), try itemLen(&.{0x05}, 0));
    // Text "hi" → 1 (head) + 2 (content) = 3
    try std.testing.expectEqual(@as(usize, 3), try itemLen(&.{ 0x62, 'h', 'i' }, 0));
    // Bytes(2) 0xDEAD → 3 bytes
    try std.testing.expectEqual(@as(usize, 3), try itemLen(&.{ 0x42, 0xDE, 0xAD }, 0));
    // Array[1, 2] → 3 bytes (head + two uints)
    try std.testing.expectEqual(@as(usize, 3), try itemLen(&.{ 0x82, 0x01, 0x02 }, 0));
    // Map{1:2} → 3 bytes
    try std.testing.expectEqual(@as(usize, 3), try itemLen(&.{ 0xA1, 0x01, 0x02 }, 0));
    // Tag(1)(uint 5) → 2 bytes head + 1 content
    try std.testing.expectEqual(@as(usize, 2), try itemLen(&.{ 0xC1, 0x05 }, 0));
}

test "PairList: sort orders shorter-first then lex" {
    const gpa = std.testing.allocator;
    var pl = PairList.init(gpa);
    defer pl.deinit();
    try pl.addText("longer-key", "v1");
    try pl.addText("a", "v2");
    try pl.addText("bb", "v3");
    try pl.addText("aa", "v4");
    pl.sort();
    try std.testing.expectEqualStrings("a", pl.pairs.items[0].key);
    try std.testing.expectEqualStrings("aa", pl.pairs.items[1].key);
    try std.testing.expectEqualStrings("bb", pl.pairs.items[2].key);
    try std.testing.expectEqualStrings("longer-key", pl.pairs.items[3].key);
}
