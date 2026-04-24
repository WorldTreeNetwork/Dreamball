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

// ─── Cursor-based readers with canonical-form enforcement ───────────────────
//
// zbor does **not** reject non-smallest-form integer encodings on decode.
// For dCBOR interop we want the decoder to reject any padded head
// (e.g. `0x18 0x05` encoding the value 5 in 2 bytes when 1 suffices, or
// `0x19 0x00 0xFF` encoding 255 in 3 bytes when 2 suffice). `readHead`
// enforces this on every head it produces, so every caller of these
// helpers inherits the check.
//
// Call `verifyCanonical(bytes)` at the top of a decode path to validate
// the entire envelope is in canonical form in one pass — cheaper than
// per-item scatter, and catches nested non-canonical encodings that a
// tree-walking decoder might miss.

pub const ReadError = error{
    Truncated,
    NonCanonicalInteger,
    UnexpectedMajorType,
    UnexpectedTag,
    UnsupportedItem,
};

pub const Head = struct { major: u3, info: u5, arg: u64 };

/// Read one CBOR head (major type + argument) at `cursor.*`, advance cursor
/// past the head, and return the decoded (major, info, arg) triple.
///
/// For majors 0..6, rejects non-smallest-form integer/length encodings per
/// dCBOR §3. For major 7, canonical-form semantics are different — `info`
/// disambiguates simple values (≤23 inline, 24 as 1-byte follow) from
/// halfs/floats/doubles (25/26/27) and floats are rejected by
/// `verifyCanonical`, not here. Indefinite-length items (info == 31) are
/// rejected for all majors.
pub fn readHead(bytes: []const u8, cursor: *usize) ReadError!Head {
    if (cursor.* >= bytes.len) return ReadError.Truncated;
    const b = bytes[cursor.*];
    cursor.* += 1;
    const major: u3 = @intCast(b >> 5);
    const info: u5 = @intCast(b & 0x1F);
    const arg: u64 = switch (info) {
        0...23 => @as(u64, info),
        24 => blk: {
            if (cursor.* >= bytes.len) return ReadError.Truncated;
            const v = bytes[cursor.*];
            cursor.* += 1;
            break :blk @as(u64, v);
        },
        25 => blk: {
            if (cursor.* + 2 > bytes.len) return ReadError.Truncated;
            const v = std.mem.readInt(u16, bytes[cursor.*..][0..2], .big);
            cursor.* += 2;
            break :blk @as(u64, v);
        },
        26 => blk: {
            if (cursor.* + 4 > bytes.len) return ReadError.Truncated;
            const v = std.mem.readInt(u32, bytes[cursor.*..][0..4], .big);
            cursor.* += 4;
            break :blk @as(u64, v);
        },
        27 => blk: {
            if (cursor.* + 8 > bytes.len) return ReadError.Truncated;
            const v = std.mem.readInt(u64, bytes[cursor.*..][0..8], .big);
            cursor.* += 8;
            break :blk v;
        },
        // 28, 29, 30 are reserved. 31 is the indefinite-length marker.
        else => return ReadError.UnsupportedItem,
    };

    // Smallest-form enforcement for integer/length arguments: applies to
    // majors 0..6 (int, neg-int, byte-string, text-string, array, map, tag).
    // Skip for major 7, where info 25/26/27 are raw float bit patterns with
    // no smallest-form meaning.
    if (major != 7) {
        switch (info) {
            24 => if (arg < 24) return ReadError.NonCanonicalInteger,
            25 => if (arg < 256) return ReadError.NonCanonicalInteger,
            26 => if (arg < 0x1_0000) return ReadError.NonCanonicalInteger,
            27 => if (arg < 0x1_0000_0000) return ReadError.NonCanonicalInteger,
            else => {},
        }
    }

    return .{ .major = major, .info = info, .arg = arg };
}

/// Peek the major type at `cursor` without advancing or validating.
pub fn peekMajor(bytes: []const u8, cursor: usize) ReadError!u3 {
    if (cursor >= bytes.len) return ReadError.Truncated;
    return @intCast(bytes[cursor] >> 5);
}

/// Read an array header (major type 4) and return the element count.
pub fn readArrayHeader(bytes: []const u8, cursor: *usize) ReadError!u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 4) return ReadError.UnexpectedMajorType;
    return h.arg;
}

/// Read a map header (major type 5) and return the pair count.
pub fn readMapHeader(bytes: []const u8, cursor: *usize) ReadError!u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 5) return ReadError.UnexpectedMajorType;
    return h.arg;
}

/// Read a tag (major type 6) and return the tag number. The tagged item
/// itself is left unconsumed at `cursor.*`.
pub fn readTag(bytes: []const u8, cursor: *usize) ReadError!u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 6) return ReadError.UnexpectedMajorType;
    return h.arg;
}

/// Read a tag and fail if it does not equal `want`.
pub fn expectTag(bytes: []const u8, cursor: *usize, want: u64) ReadError!void {
    const got = try readTag(bytes, cursor);
    if (got != want) return ReadError.UnexpectedTag;
}

/// Read an unsigned integer (major type 0).
pub fn readUint(bytes: []const u8, cursor: *usize) ReadError!u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 0) return ReadError.UnexpectedMajorType;
    return h.arg;
}

/// Read a text string (major type 3) and return a borrowed slice into `bytes`.
pub fn readText(bytes: []const u8, cursor: *usize) ReadError![]const u8 {
    const h = try readHead(bytes, cursor);
    if (h.major != 3) return ReadError.UnexpectedMajorType;
    const len: usize = @intCast(h.arg);
    if (cursor.* + len > bytes.len) return ReadError.Truncated;
    const s = bytes[cursor.* .. cursor.* + len];
    cursor.* += len;
    return s;
}

/// Read a byte string (major type 2) and return a borrowed slice into `bytes`.
pub fn readBytes(bytes: []const u8, cursor: *usize) ReadError![]const u8 {
    const h = try readHead(bytes, cursor);
    if (h.major != 2) return ReadError.UnexpectedMajorType;
    const len: usize = @intCast(h.arg);
    if (cursor.* + len > bytes.len) return ReadError.Truncated;
    const s = bytes[cursor.* .. cursor.* + len];
    cursor.* += len;
    return s;
}

/// Read an f16 (half-float, major 7 info 25, `0xF9` prefix).
pub fn readF16(bytes: []const u8, cursor: *usize) ReadError!f16 {
    const h = try readHead(bytes, cursor);
    if (h.major != 7 or h.info != 25) return ReadError.UnexpectedMajorType;
    return @bitCast(@as(u16, @intCast(h.arg)));
}

/// Read an f32 (single-float, major 7 info 26, `0xFA` prefix).
pub fn readF32(bytes: []const u8, cursor: *usize) ReadError!f32 {
    const h = try readHead(bytes, cursor);
    if (h.major != 7 or h.info != 26) return ReadError.UnexpectedMajorType;
    return @bitCast(@as(u32, @intCast(h.arg)));
}

/// Read an f64 (double-float, major 7 info 27, `0xFB` prefix).
pub fn readF64(bytes: []const u8, cursor: *usize) ReadError!f64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 7 or h.info != 27) return ReadError.UnexpectedMajorType;
    return @bitCast(h.arg);
}

/// Read any float (f16, f32, or f64) and return as f64. Accepts all three
/// widths and widens to f64. Used by decoders that store f64 values.
pub fn readAnyFloat(bytes: []const u8, cursor: *usize) ReadError!f64 {
    if (cursor.* >= bytes.len) return ReadError.Truncated;
    const b = bytes[cursor.*];
    const info: u5 = @intCast(b & 0x1F);
    const major: u3 = @intCast(b >> 5);
    if (major != 7) return ReadError.UnexpectedMajorType;
    return switch (info) {
        25 => @floatCast(try readF16(bytes, cursor)),
        26 => @floatCast(try readF32(bytes, cursor)),
        27 => try readF64(bytes, cursor),
        else => ReadError.UnexpectedMajorType,
    };
}

/// Read any float and return as f32 (widening from f16 accepted).
pub fn readAnyFloatF32(bytes: []const u8, cursor: *usize) ReadError!f32 {
    return @floatCast(try readAnyFloat(bytes, cursor));
}

/// Write a float using the smallest half/single encoding that is lossless.
/// - If the value round-trips through f16 without change → emit #7.25.
/// - Otherwise emit #7.26 (f32).
/// Used for aqueduct and layout/trust float fields per TC20.
pub fn writeSmallestFloat(w: *std.Io.Writer, v: f32) !void {
    const as_half: f16 = @floatCast(v);
    const back: f32 = @floatCast(as_half);
    if (back == v) {
        try zbor.builder.writeFloat(w, as_half);
    } else {
        try zbor.builder.writeFloat(w, v);
    }
}

/// Skip one item at `cursor.*` without examining its structure. Uses
/// `zbor.advance` for well-formedness; does NOT enforce canonical form.
/// Use `verifyCanonical` first if you need that guarantee for nested items.
pub fn skipItem(bytes: []const u8, cursor: *usize) ReadError!void {
    if (cursor.* >= bytes.len) return ReadError.Truncated;
    if (zbor.advance(bytes, cursor) == null) return ReadError.Truncated;
}

/// Walk the entire CBOR stream in `bytes`, validating every head is in
/// smallest form per dCBOR §3 AND that every map's keys appear in
/// canonical (shorter-first, then lexicographic) order per RFC 8949 §4.2.1.
/// Accepts any number of top-level items.  Returns on the first
/// non-canonical head, out-of-order map key, or malformed item.
///
/// Intended for use at the top of a decode path — e.g. every `decode*`
/// in envelope_v2.zig runs this once on the whole envelope so later
/// readers can trust that the bytes are canonical (both smallest-form
/// AND map-key-ordered).
///
/// Load-bearing rationale: without map-key-order enforcement two
/// byte-distinct encodings decode to the same logical struct but hash
/// to different Blake3 fingerprints — which breaks parent-hash checks
/// and opens the door to malleability / forgery. See review note
/// HIGH-1 in the Sprint-1 code review (2026-04-24) for the full
/// rationale.
pub fn verifyCanonical(bytes: []const u8) ReadError!void {
    var cursor: usize = 0;
    while (cursor < bytes.len) {
        try verifyOne(bytes, &cursor);
    }
}

/// Canonical map-key ordering comparison per RFC 8949 §4.2.1 / dCBOR:
/// the key with the shorter encoded form sorts first; ties break
/// lexicographically over the raw encoded bytes.
fn keyLessThan(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return a.len < b.len;
    return std.mem.lessThan(u8, a, b);
}

fn verifyOne(bytes: []const u8, cursor: *usize) ReadError!void {
    const head = try readHead(bytes, cursor);
    switch (head.major) {
        0, 1 => {}, // int — head-only, no content to walk
        2, 3 => {
            // byte/text string: skip content bytes
            const len: usize = @intCast(head.arg);
            if (cursor.* + len > bytes.len) return ReadError.Truncated;
            cursor.* += len;
        },
        4 => {
            // array: recurse for each element
            var i: u64 = 0;
            while (i < head.arg) : (i += 1) try verifyOne(bytes, cursor);
        },
        5 => {
            // map: recurse for each key and each value, verifying that
            // the raw CBOR encoding of each successive key sorts AFTER
            // the previous key under RFC 8949 §4.2.1.  We snapshot the
            // cursor before and after the key's head+content so we can
            // slice the exact bytes compared.
            var i: u64 = 0;
            var prev_key_start: usize = 0;
            var prev_key_end: usize = 0;
            while (i < head.arg) : (i += 1) {
                const key_start = cursor.*;
                try verifyOne(bytes, cursor); // key
                const key_end = cursor.*;
                if (i > 0) {
                    const prev_key = bytes[prev_key_start..prev_key_end];
                    const this_key = bytes[key_start..key_end];
                    // Strictly-less: equal-key is also illegal (duplicate
                    // map keys are a dCBOR violation).
                    if (!keyLessThan(prev_key, this_key)) {
                        return ReadError.NonCanonicalInteger;
                    }
                }
                prev_key_start = key_start;
                prev_key_end = key_end;
                try verifyOne(bytes, cursor); // value
            }
        },
        6 => {
            // tag: recurse once into the tagged item
            try verifyOne(bytes, cursor);
        },
        7 => {
            // Only inline simple values 20–23 (false/true/null/undefined)
            // are permitted. info 24 (extended simple) and info 25/26/27
            // (f16/f32/f64) are rejected — DreamBall envelopes never use
            // them.
            if (head.info > 23) return ReadError.UnsupportedItem;
            if (head.arg != 20 and head.arg != 21 and head.arg != 22 and head.arg != 23) {
                return ReadError.UnsupportedItem;
            }
        },
    }
}

/// Variant of `verifyCanonical` that allows floats (major 7 info 25/26/27).
/// Used for envelope types that legitimately carry float values under the
/// PROTOCOL §12.2 float exception (omnispherical-grid, layout, aqueduct,
/// emotional-register, trust-observation).  All other canonicality rules —
/// smallest-form integer encoding and map-key ordering — remain in force.
pub fn verifyCanonicalAllowFloats(bytes: []const u8) ReadError!void {
    var cursor: usize = 0;
    while (cursor < bytes.len) {
        try verifyOneAllowFloats(bytes, &cursor);
    }
}

fn verifyOneAllowFloats(bytes: []const u8, cursor: *usize) ReadError!void {
    const head = try readHead(bytes, cursor);
    switch (head.major) {
        0, 1 => {},
        2, 3 => {
            const len: usize = @intCast(head.arg);
            if (cursor.* + len > bytes.len) return ReadError.Truncated;
            cursor.* += len;
        },
        4 => {
            var i: u64 = 0;
            while (i < head.arg) : (i += 1) try verifyOneAllowFloats(bytes, cursor);
        },
        5 => {
            var i: u64 = 0;
            var prev_key_start: usize = 0;
            var prev_key_end: usize = 0;
            while (i < head.arg) : (i += 1) {
                const key_start = cursor.*;
                try verifyOneAllowFloats(bytes, cursor);
                const key_end = cursor.*;
                if (i > 0) {
                    const prev_key = bytes[prev_key_start..prev_key_end];
                    const this_key = bytes[key_start..key_end];
                    if (!keyLessThan(prev_key, this_key)) {
                        return ReadError.NonCanonicalInteger;
                    }
                }
                prev_key_start = key_start;
                prev_key_end = key_end;
                try verifyOneAllowFloats(bytes, cursor);
            }
        },
        6 => try verifyOneAllowFloats(bytes, cursor),
        7 => {
            // Permit floats (info 25/26/27) in addition to bools/null/undefined.
            if (head.info == 25 or head.info == 26 or head.info == 27) return;
            if (head.info > 23) return ReadError.UnsupportedItem;
            if (head.arg != 20 and head.arg != 21 and head.arg != 22 and head.arg != 23) {
                return ReadError.UnsupportedItem;
            }
        },
    }
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

test "readHead rejects 1-byte-padded uint (info 24, value <24)" {
    // `0x18 0x05` encodes value 5 in the 1-byte-follow form; minimum is `0x05`.
    var cursor: usize = 0;
    const bytes = [_]u8{ 0x18, 0x05 };
    try std.testing.expectError(ReadError.NonCanonicalInteger, readHead(&bytes, &cursor));
}

test "readHead rejects 2-byte-padded uint (info 25, value <256)" {
    // `0x19 0x00 0xFF` encodes value 255 in the 2-byte form; minimum is `0x18 0xFF`.
    var cursor: usize = 0;
    const bytes = [_]u8{ 0x19, 0x00, 0xFF };
    try std.testing.expectError(ReadError.NonCanonicalInteger, readHead(&bytes, &cursor));
}

test "readHead rejects 4-byte-padded uint (info 26, value <65536)" {
    // `0x1A 0x00 0x00 0x01 0x00` encodes value 256 in the 4-byte form; minimum is `0x19 0x01 0x00`.
    var cursor: usize = 0;
    const bytes = [_]u8{ 0x1A, 0x00, 0x00, 0x01, 0x00 };
    try std.testing.expectError(ReadError.NonCanonicalInteger, readHead(&bytes, &cursor));
}

test "readHead rejects 8-byte-padded uint (info 27, value <2^32)" {
    var cursor: usize = 0;
    const bytes = [_]u8{ 0x1B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00 };
    try std.testing.expectError(ReadError.NonCanonicalInteger, readHead(&bytes, &cursor));
}

test "readHead accepts smallest-form encodings at each boundary" {
    // info < 24
    {
        var cursor: usize = 0;
        const h = try readHead(&[_]u8{0x17}, &cursor);
        try std.testing.expectEqual(@as(u64, 23), h.arg);
    }
    // info 24 at lower bound (24)
    {
        var cursor: usize = 0;
        const h = try readHead(&[_]u8{ 0x18, 0x18 }, &cursor);
        try std.testing.expectEqual(@as(u64, 24), h.arg);
    }
    // info 25 at lower bound (256)
    {
        var cursor: usize = 0;
        const h = try readHead(&[_]u8{ 0x19, 0x01, 0x00 }, &cursor);
        try std.testing.expectEqual(@as(u64, 256), h.arg);
    }
    // info 26 at lower bound (65536)
    {
        var cursor: usize = 0;
        const h = try readHead(&[_]u8{ 0x1A, 0x00, 0x01, 0x00, 0x00 }, &cursor);
        try std.testing.expectEqual(@as(u64, 0x1_0000), h.arg);
    }
    // info 27 at lower bound (2^32)
    {
        var cursor: usize = 0;
        const h = try readHead(&[_]u8{ 0x1B, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 }, &cursor);
        try std.testing.expectEqual(@as(u64, 0x1_0000_0000), h.arg);
    }
}

test "readHead rejects indefinite-length marker (info 31)" {
    var cursor: usize = 0;
    // Major 4 (array), info 31 = `0x9F` = indefinite-length array.
    const bytes = [_]u8{0x9F};
    try std.testing.expectError(ReadError.UnsupportedItem, readHead(&bytes, &cursor));
}

test "verifyCanonical accepts canonical fixture" {
    // A tiny canonical envelope: tag(200)([tag(201)({"t":1}),]).
    // Hand-built to be canonical.
    const bytes = [_]u8{
        0xD8, 0xC8, // tag 200
        0x81, //       array(1)
        0xD8, 0xC9, // tag 201
        0xA1, //       map(1)
        0x61, 't', //  "t"
        0x01, //       1
    };
    try verifyCanonical(&bytes);
}

test "verifyCanonical rejects non-canonical nested uint" {
    // Same envelope, but the `1` value is encoded as `0x18 0x01` (padded).
    const bytes = [_]u8{
        0xD8, 0xC8, //
        0x81, //
        0xD8, 0xC9, //
        0xA1, //
        0x61, 't', //
        0x18, 0x01, // <- non-canonical
    };
    try std.testing.expectError(ReadError.NonCanonicalInteger, verifyCanonical(&bytes));
}

test "verifyCanonical rejects nested indefinite-length array" {
    // tag(200) wrapping an indefinite-length array.
    const bytes = [_]u8{ 0xD8, 0xC8, 0x9F, 0x01, 0xFF };
    try std.testing.expectError(ReadError.UnsupportedItem, verifyCanonical(&bytes));
}

test "verifyCanonical accepts bools and simple null/undefined" {
    // Array of [true, false, null, undefined].
    const bytes = [_]u8{ 0x84, 0xF5, 0xF4, 0xF6, 0xF7 };
    try verifyCanonical(&bytes);
}

test "verifyCanonical rejects float (major 7, info 26)" {
    // f32 0.0
    const bytes = [_]u8{ 0xFA, 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectError(ReadError.UnsupportedItem, verifyCanonical(&bytes));
}

test "readArrayHeader / readMapHeader / readTag / readUint / readText / readBytes smoke" {
    // [1, 2] — array of 2, with uints.
    {
        var cursor: usize = 0;
        const bytes = [_]u8{ 0x82, 0x01, 0x02 };
        try std.testing.expectEqual(@as(u64, 2), try readArrayHeader(&bytes, &cursor));
        try std.testing.expectEqual(@as(u64, 1), try readUint(&bytes, &cursor));
        try std.testing.expectEqual(@as(u64, 2), try readUint(&bytes, &cursor));
    }
    // {"x": 5}
    {
        var cursor: usize = 0;
        const bytes = [_]u8{ 0xA1, 0x61, 'x', 0x05 };
        try std.testing.expectEqual(@as(u64, 1), try readMapHeader(&bytes, &cursor));
        try std.testing.expectEqualStrings("x", try readText(&bytes, &cursor));
        try std.testing.expectEqual(@as(u64, 5), try readUint(&bytes, &cursor));
    }
    // tag 200 over bytes `DEAD`
    {
        var cursor: usize = 0;
        const bytes = [_]u8{ 0xD8, 0xC8, 0x42, 0xDE, 0xAD };
        try expectTag(&bytes, &cursor, 200);
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD }, try readBytes(&bytes, &cursor));
    }
    // expectTag mismatch
    {
        var cursor: usize = 0;
        const bytes = [_]u8{ 0xD8, 0xC8 };
        try std.testing.expectError(ReadError.UnexpectedTag, expectTag(&bytes, &cursor, 201));
    }
}

test "verifyCanonical accepts map with canonically-ordered keys" {
    // {"a": 1, "bb": 2} — len 1 < len 2, so "a" first is canonical.
    const bytes = [_]u8{
        0xA2, //       map(2)
        0x61, 'a', //  "a"
        0x01, //       1
        0x62, 'b', 'b', // "bb"
        0x02, //       2
    };
    try verifyCanonical(&bytes);
}

test "verifyCanonical rejects map with non-canonical key order (length violation)" {
    // {"bb": 2, "a": 1} — len-2 key first, len-1 key second.  Violation.
    const bytes = [_]u8{
        0xA2,
        0x62, 'b', 'b',
        0x02,
        0x61, 'a',
        0x01,
    };
    try std.testing.expectError(ReadError.NonCanonicalInteger, verifyCanonical(&bytes));
}

test "verifyCanonical rejects map with non-canonical key order (lex violation within equal length)" {
    // {"bb": 2, "aa": 1} — equal length, but "bb" > "aa" lex.  Violation.
    const bytes = [_]u8{
        0xA2,
        0x62, 'b', 'b',
        0x02,
        0x62, 'a', 'a',
        0x01,
    };
    try std.testing.expectError(ReadError.NonCanonicalInteger, verifyCanonical(&bytes));
}

test "verifyCanonical rejects map with duplicate keys" {
    // {"a": 1, "a": 2} — same key twice.  dCBOR prohibits duplicates.
    const bytes = [_]u8{
        0xA2,
        0x61, 'a',
        0x01,
        0x61, 'a',
        0x02,
    };
    try std.testing.expectError(ReadError.NonCanonicalInteger, verifyCanonical(&bytes));
}

test "verifyCanonical rejects nested non-canonical map-key ordering" {
    // tag(200)([tag(201)({"bb": 2, "a": 1})]) — inner map has wrong order.
    const bytes = [_]u8{
        0xD8, 0xC8, // tag 200
        0x81, //       array(1)
        0xD8, 0xC9, // tag 201
        0xA2, //       map(2)
        0x62, 'b', 'b',
        0x02,
        0x61, 'a',
        0x01,
    };
    try std.testing.expectError(ReadError.NonCanonicalInteger, verifyCanonical(&bytes));
}

test "verifyCanonicalAllowFloats accepts an f32 but rejects bad map order" {
    // f32 0.5
    const ok_bytes = [_]u8{ 0xFA, 0x3F, 0x00, 0x00, 0x00 };
    try verifyCanonicalAllowFloats(&ok_bytes);
    // Same map-ordering check applies.
    const bad_bytes = [_]u8{
        0xA2,
        0x62, 'b', 'b',
        0x02,
        0x61, 'a',
        0x01,
    };
    try std.testing.expectError(ReadError.NonCanonicalInteger, verifyCanonicalAllowFloats(&bad_bytes));
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
