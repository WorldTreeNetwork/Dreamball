//! mythos-chain.zig — pure walk-to-genesis verifier utility.
//!
//! Exported for use by `jelly verify` (S3.6 `palace_verify.zig` imports
//! this directly — no copy). See docs/PROTOCOL.md §13.8 mythos semantics
//! and Story 3.4 AC6 / TC18.
//!
//! Canonical mythos (the kind managed by `jelly palace rename-mythos`) form
//! a single append-only chain: genesis → successor → successor → …. Each
//! successor carries a `predecessor` field that is the Blake3 fingerprint of
//! the prior canonical mythos envelope. There MUST be exactly one genesis in
//! any valid chain (is-genesis: true, no predecessor).
//!
//! Poetic mythoi (attached to inscriptions, rooms, or other objects) live
//! outside this chain and are intentionally NOT checked here (TC18 split).
//!
//! Design: `walkToGenesis` takes only a CAS lookup function and the head fp.
//! It does not depend on LadybugDB / any store adapter. This keeps it usable
//! from both the Zig CLI verifier and unit tests without any DB dependency.
//!
//! CAS lookup function contract:
//!   Given a Blake3 fp (32 bytes), return the raw CBOR envelope bytes if
//!   present, or null if the fp is not in the CAS.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Result type (AC6 tagged-union shape) ──────────────────────────────────────

/// Returned by walkToGenesis.
pub const GenesisResult = union(enum) {
    /// Happy path — one genesis found, chain fully resolved.
    ok: struct {
        genesis_fp: [32]u8,
        depth: usize,
    },
    /// Chain broken — a predecessor fp is not present in the CAS.
    unresolvable_predecessor: [32]u8,
    /// Two nodes in the chain both claim is-genesis: true.
    /// `first` is the genesis encountered later in the walk (closer to head);
    /// `second` is the one encountered earlier (deeper in chain).
    multiple_genesis: struct {
        first: [32]u8,
        second: [32]u8,
    },
};

// ── CAS lookup function type ──────────────────────────────────────────────────

/// Caller supplies a lookup function. Returns null if fp not in CAS.
pub const CasLookupFn = *const fn (fp: *const [32]u8, userdata: ?*anyopaque) ?[]const u8;

// ── Minimal CBOR parser for mythos fields ────────────────────────────────────
//
// We only need to extract two fields from a jelly.mythos envelope:
//   - is-genesis (bool)
//   - predecessor (optional 32-byte bstr)
//
// Full CBOR parsing via zbor is available but pulling the entire zbor stack
// into a pure utility creates a heavyweight dep. Instead we use a small
// hand-rolled scanner that reads just the two fields we care about from the
// dCBOR canonical encoding. This is safe because:
//   (a) We only accept bytes from our own CAS — they were written by our
//       own encoders, which produce canonical dCBOR.
//   (b) We stop at the first unknown field by skipping, not failing.
//
// If more fields are ever needed, replace with zbor decode.

const CBOR_TAG_UINT: u8 = 0x00;
const CBOR_MAJOR_UINT: u8 = 0x00;
const CBOR_MAJOR_BSTR: u8 = 0x40;
const CBOR_MAJOR_TSTR: u8 = 0x60;
const CBOR_MAJOR_ARR: u8 = 0x80;
const CBOR_MAJOR_MAP: u8 = 0xa0;
const CBOR_MAJOR_TAG: u8 = 0xc0;
const CBOR_SIMPLE_FALSE: u8 = 0xf4;
const CBOR_SIMPLE_TRUE: u8 = 0xf5;
const CBOR_SIMPLE_NULL: u8 = 0xf6;
const CBOR_BREAK: u8 = 0xff;

/// Minimal CBOR scanner errors.
const ScanError = error{
    EndOfBuffer,
    InvalidCbor,
};

/// Read one CBOR item from `buf[pos..*]`. Returns the byte length consumed.
/// Recurses for nested arrays/maps/tags.
fn skipCborItem(buf: []const u8, pos: usize) ScanError!usize {
    if (pos >= buf.len) return error.EndOfBuffer;
    const ib = buf[pos];
    const major = ib & 0xe0;
    const info = ib & 0x1f;

    // Determine argument size.
    var arg: u64 = 0;
    var header_len: usize = 1;
    switch (info) {
        0...23 => { arg = info; },
        24 => {
            if (pos + 1 >= buf.len) return error.EndOfBuffer;
            arg = buf[pos + 1];
            header_len = 2;
        },
        25 => {
            if (pos + 2 >= buf.len) return error.EndOfBuffer;
            arg = @as(u64, buf[pos + 1]) << 8 | buf[pos + 2];
            header_len = 3;
        },
        26 => {
            if (pos + 4 >= buf.len) return error.EndOfBuffer;
            arg = @as(u64, buf[pos + 1]) << 24 |
                  @as(u64, buf[pos + 2]) << 16 |
                  @as(u64, buf[pos + 3]) << 8 |
                  buf[pos + 4];
            header_len = 5;
        },
        27 => {
            if (pos + 8 >= buf.len) return error.EndOfBuffer;
            arg = @as(u64, buf[pos + 1]) << 56 |
                  @as(u64, buf[pos + 2]) << 48 |
                  @as(u64, buf[pos + 3]) << 40 |
                  @as(u64, buf[pos + 4]) << 32 |
                  @as(u64, buf[pos + 5]) << 24 |
                  @as(u64, buf[pos + 6]) << 16 |
                  @as(u64, buf[pos + 7]) << 8 |
                  buf[pos + 8];
            header_len = 9;
        },
        // indefinite not used in dCBOR; treat as invalid.
        else => return error.InvalidCbor,
    }

    switch (major) {
        CBOR_MAJOR_UINT, 0x20 => { // uint or nint
            return header_len;
        },
        CBOR_MAJOR_BSTR, CBOR_MAJOR_TSTR => { // bstr or tstr
            const total = header_len + @as(usize, @intCast(arg));
            if (pos + total > buf.len) return error.EndOfBuffer;
            return total;
        },
        CBOR_MAJOR_ARR => { // array
            var off = pos + header_len;
            for (0..@as(usize, @intCast(arg))) |_| {
                off += try skipCborItem(buf, off);
            }
            return off - pos;
        },
        CBOR_MAJOR_MAP => { // map
            var off = pos + header_len;
            for (0..@as(usize, @intCast(arg))) |_| {
                off += try skipCborItem(buf, off); // key
                off += try skipCborItem(buf, off); // value
            }
            return off - pos;
        },
        CBOR_MAJOR_TAG => { // tag — skip tag number, then scan tagged item
            return header_len + try skipCborItem(buf, pos + header_len);
        },
        0xe0 => { // simple / float
            // simple values (false/true/null/break) encoded in info bits
            return header_len;
        },
        else => return error.InvalidCbor,
    }
}

/// Read a text-string key from buf[pos]. Returns (key_bytes, consumed_len).
fn readTstr(buf: []const u8, pos: usize) ScanError!struct { key: []const u8, len: usize } {
    if (pos >= buf.len) return error.EndOfBuffer;
    const ib = buf[pos];
    if ((ib & 0xe0) != CBOR_MAJOR_TSTR) return error.InvalidCbor;
    const info = ib & 0x1f;
    var slen: u64 = 0;
    var hlen: usize = 1;
    switch (info) {
        0...23 => { slen = info; },
        24 => {
            if (pos + 1 >= buf.len) return error.EndOfBuffer;
            slen = buf[pos + 1];
            hlen = 2;
        },
        else => return error.InvalidCbor,
    }
    const start = pos + hlen;
    const end = start + @as(usize, @intCast(slen));
    if (end > buf.len) return error.EndOfBuffer;
    return .{ .key = buf[start..end], .len = hlen + @as(usize, @intCast(slen)) };
}

/// Parsed fields from a jelly.mythos envelope.
const MythosFields = struct {
    is_genesis: bool = false,
    predecessor: ?[32]u8 = null,
};

/// Scan the CBOR bytes of a jelly.mythos envelope and extract is-genesis and
/// predecessor. Tolerates extra fields (open-schema rule).
///
/// The dCBOR encoding emitted by `envelope_v2.encodeMythos` is:
///   tag(200) [ tag(201){map{ "type", "is-genesis", "format-version" }}, attribute-arrays… ]
/// Attributes that carry predecessor:
///   [2]( "predecessor", bstr[32] )
/// Attributes that carry is-genesis:
///   The core map already has "is-genesis" → bool.
///
/// We scan two places:
///   1. The core map (tag 201) for "is-genesis".
///   2. Any 2-element [label, value] attribute for "predecessor".
fn parseMythosFields(buf: []const u8) !MythosFields {
    var fields = MythosFields{};
    if (buf.len < 2) return fields;

    // Outer: tag(200) — skip the tag header.
    var pos: usize = 0;
    if (pos >= buf.len) return fields;
    // Skip the tag(200) wrapper.
    if ((buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += try skipCborItem(buf[0..], pos);
        // That skipped the whole thing. Re-enter manually.
        // We need fine-grained access, so restart with manual header skip.
    }

    // The dCBOR envelope is tag(200)( array[ tag(201)(map{...}), attr1, attr2, ... ] ).
    // Use a simpler approach: scan the flat byte stream for known patterns.
    //
    // Strategy: find the tag(201) item, read its map for "is-genesis",
    // then scan subsequent [2][tstr, value] pairs for "predecessor".

    pos = 0;

    // Skip tag(200) header (1 or 2 bytes depending on tag number encoding).
    // Tag 200 = 0xC0 | 24 + 0xC8 = 0xD8 0xC8
    if (pos < buf.len and buf[pos] == 0xD8) {
        pos += 2; // tag 200: 0xD8 0xC8
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        // Skip any other single-byte tag header.
        pos += 1;
    }

    // Now we should be at the array header.
    if (pos >= buf.len) return fields;
    if ((buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return fields;
    const arr_info = buf[pos] & 0x1f;
    var arr_count: u64 = 0;
    var arr_hlen: usize = 1;
    switch (arr_info) {
        0...23 => { arr_count = arr_info; },
        24 => {
            if (pos + 1 >= buf.len) return fields;
            arr_count = buf[pos + 1];
            arr_hlen = 2;
        },
        else => return fields,
    }
    pos += arr_hlen;

    // First element: tag(201)(map{...}) — the core.
    if (pos >= buf.len) return fields;
    // Skip tag(201) header: 0xD8 0xC9
    if (pos + 1 < buf.len and buf[pos] == 0xD8 and buf[pos + 1] == 0xC9) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    }

    // Now at the core map.
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_MAP) return fields;
    const map_info = buf[pos] & 0x1f;
    var map_count: u64 = 0;
    var map_hlen: usize = 1;
    switch (map_info) {
        0...23 => { map_count = map_info; },
        24 => {
            if (pos + 1 >= buf.len) return fields;
            map_count = buf[pos + 1];
            map_hlen = 2;
        },
        else => return fields,
    }
    pos += map_hlen;

    // Read map key-value pairs.
    for (0..@as(usize, @intCast(map_count))) |_| {
        if (pos >= buf.len) break;
        const key_res = readTstr(buf, pos) catch break;
        pos += key_res.len;
        if (std.mem.eql(u8, key_res.key, "is-genesis")) {
            if (pos < buf.len) {
                fields.is_genesis = buf[pos] == CBOR_SIMPLE_TRUE;
                pos += try skipCborItem(buf, pos);
            }
        } else {
            // Skip value.
            pos += skipCborItem(buf, pos) catch break;
        }
    }

    // Remaining elements: 2-element arrays [label, value].
    for (1..@as(usize, @intCast(arr_count))) |_| {
        if (pos >= buf.len) break;
        // Should be array(2).
        if ((buf[pos] & 0xe0) != CBOR_MAJOR_ARR) {
            pos += skipCborItem(buf, pos) catch break;
            continue;
        }
        const el_info = buf[pos] & 0x1f;
        if (el_info != 2) {
            pos += skipCborItem(buf, pos) catch break;
            continue;
        }
        pos += 1; // array(2) header

        // Read label.
        if (pos >= buf.len) break;
        const lbl_res = readTstr(buf, pos) catch {
            pos += skipCborItem(buf, pos) catch break;
            pos += skipCborItem(buf, pos) catch break;
            continue;
        };
        pos += lbl_res.len;

        if (std.mem.eql(u8, lbl_res.key, "predecessor")) {
            // Value should be bstr[32].
            if (pos >= buf.len) break;
            const vib = buf[pos];
            if ((vib & 0xe0) == CBOR_MAJOR_BSTR) {
                const vinfo = vib & 0x1f;
                var vlen: usize = 0;
                var vhlen: usize = 1;
                if (vinfo <= 23) {
                    vlen = vinfo;
                } else if (vinfo == 24) {
                    if (pos + 1 >= buf.len) break;
                    vlen = buf[pos + 1];
                    vhlen = 2;
                }
                if (vlen == 32) {
                    const vstart = pos + vhlen;
                    if (vstart + 32 <= buf.len) {
                        var pred: [32]u8 = undefined;
                        @memcpy(&pred, buf[vstart .. vstart + 32]);
                        fields.predecessor = pred;
                    }
                }
                pos += vhlen + vlen;
            } else {
                pos += skipCborItem(buf, pos) catch break;
            }
        } else {
            // Skip the value.
            pos += skipCborItem(buf, pos) catch break;
        }
    }

    return fields;
}

// ── walkToGenesis ─────────────────────────────────────────────────────────────

/// Walk the canonical mythos chain from `head_fp` back to the genesis node.
///
/// Algorithm:
///   1. Resolve head_fp from CAS. If missing → unresolvable_predecessor.
///   2. Parse is-genesis and predecessor fields.
///   3. If is_genesis and no predecessor seen yet → ok (happy path).
///   4. If is_genesis and genesis already seen → multiple_genesis.
///   5. If predecessor absent and not is_genesis → treat as unresolvable (malformed chain).
///   6. Recurse on predecessor fp.
///
/// `depth_limit` prevents infinite loops (broken chain cycle). 1024 is
/// generous; a palace would need 1024 renames to hit it.
///
/// `userdata` is forwarded to the CAS lookup function.
pub fn walkToGenesis(
    lookup: CasLookupFn,
    userdata: ?*anyopaque,
    head_fp: *const [32]u8,
) GenesisResult {
    const depth_limit: usize = 1024;

    var current_fp: [32]u8 = head_fp.*;
    var depth: usize = 0;
    // Track the first genesis seen when walking from head toward root.
    // A valid chain has exactly one genesis (the deepest node).
    // If a node claims is_genesis but still has a predecessor, we record it here
    // and continue walking; if we find another genesis deeper, we report multiple_genesis.
    var first_genesis_fp: ?[32]u8 = null;

    while (depth < depth_limit) : (depth += 1) {
        const bytes = lookup(&current_fp, userdata) orelse {
            // If we already found a genesis but the chain has no predecessor (it would
            // have returned ok below), this means the predecessor fp after the genesis is
            // unresolvable — which shouldn't happen in a well-formed chain, but handle it.
            return .{ .unresolvable_predecessor = current_fp };
        };

        const fields = parseMythosFields(bytes) catch {
            // Malformed envelope — treat as unresolvable.
            return .{ .unresolvable_predecessor = current_fp };
        };

        if (fields.is_genesis) {
            if (first_genesis_fp) |first| {
                // A second node claims is_genesis: true — chain invariant violated.
                return .{ .multiple_genesis = .{ .first = first, .second = current_fp } };
            }

            if (fields.predecessor == null) {
                // Normal case: genesis with no predecessor → happy path.
                return .{ .ok = .{ .genesis_fp = current_fp, .depth = depth + 1 } };
            }

            // Unusual: is_genesis=true but also has a predecessor.
            // Record as the first genesis seen and continue walking to detect duplicates.
            first_genesis_fp = current_fp;
            const pred = fields.predecessor.?;
            current_fp = pred;
            continue;
        }

        const pred = fields.predecessor orelse {
            // Not genesis, no predecessor — malformed chain.
            return .{ .unresolvable_predecessor = current_fp };
        };
        current_fp = pred;
    }

    // Exceeded depth limit — treat as unresolvable (cycle or pathological chain).
    return .{ .unresolvable_predecessor = current_fp };
}

// ============================================================================
// Tests — AC6: ≥3 Zig tests covering (a) single-genesis, (b) unresolvable,
//               (c) two-genesis-in-chain.
// ============================================================================

// ── Test helpers ──────────────────────────────────────────────────────────────

const TestCas = struct {
    entries: std.StringHashMap([]const u8),
    allocator: Allocator,

    fn init(allocator: Allocator) TestCas {
        return .{
            .entries = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *TestCas) void {
        self.entries.deinit();
    }

    fn put(self: *TestCas, fp: *const [32]u8, bytes: []const u8) !void {
        try self.entries.put(fp, bytes);
    }

    fn lookup(fp: *const [32]u8, userdata: ?*anyopaque) ?[]const u8 {
        const cas: *TestCas = @ptrCast(@alignCast(userdata.?));
        return cas.entries.get(fp);
    }
};

/// Build a minimal dCBOR-encoded jelly.mythos envelope for testing.
/// Only encodes the fields walkToGenesis cares about.
fn buildTestMythosBytes(
    allocator: Allocator,
    is_genesis: bool,
    predecessor: ?*const [32]u8,
) ![]u8 {
    // We build a hand-crafted dCBOR bytes that parseMythosFields can read.
    // Format: tag(200) [ tag(201) {map("is-genesis"→bool, "type"→"jelly.mythos", "format-version"→2)},
    //                    optional ["predecessor", bstr[32]] ]
    const zbor = @import("zbor");
    const dcbor_mod = @import("../dcbor.zig");

    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;

    const attr_count: u64 = if (predecessor != null) 1 else 0;

    try zbor.builder.writeTag(w, dcbor_mod.Tag.envelope);
    try zbor.builder.writeArray(w, 1 + attr_count);

    // Core: tag(201) { map of 3 }
    try zbor.builder.writeTag(w, dcbor_mod.Tag.leaf);
    // "format-version"(14) > "is-genesis"(10) > "type"(4)
    // canonical order: "type"(4), "is-genesis"(10), "format-version"(14)
    try zbor.builder.writeMap(w, 3);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "jelly.mythos");
    try zbor.builder.writeTextString(w, "is-genesis");
    if (is_genesis) {
        try zbor.builder.writeTrue(w);
    } else {
        try zbor.builder.writeFalse(w);
    }
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @as(u64, 2));

    // Attribute: predecessor
    if (predecessor) |pred| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "predecessor");
        try zbor.builder.writeByteString(w, pred);
    }

    return ai.toOwnedSlice();
}

/// Blake3 hash of bytes.
fn blake3Hash(bytes: []const u8) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(bytes);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

// ── Test (a): single-genesis happy path ──────────────────────────────────────

test "walkToGenesis: single-genesis happy path" {
    const allocator = std.testing.allocator;

    // Build: genesis M0 ← M1 ← M2 (head)
    const m0_bytes = try buildTestMythosBytes(allocator, true, null);
    defer allocator.free(m0_bytes);
    const m0_fp = blake3Hash(m0_bytes);

    const m1_bytes = try buildTestMythosBytes(allocator, false, &m0_fp);
    defer allocator.free(m1_bytes);
    const m1_fp = blake3Hash(m1_bytes);

    const m2_bytes = try buildTestMythosBytes(allocator, false, &m1_fp);
    defer allocator.free(m2_bytes);
    const m2_fp = blake3Hash(m2_bytes);

    var cas = TestCas.init(allocator);
    defer cas.deinit();
    try cas.put(&m0_fp, m0_bytes);
    try cas.put(&m1_fp, m1_bytes);
    try cas.put(&m2_fp, m2_bytes);

    const result = walkToGenesis(TestCas.lookup, &cas, &m2_fp);
    switch (result) {
        .ok => |r| {
            try std.testing.expectEqualSlices(u8, &m0_fp, &r.genesis_fp);
            try std.testing.expectEqual(@as(usize, 3), r.depth);
        },
        else => return error.TestUnexpectedResult,
    }
}

// ── Test (b): unresolvable predecessor ───────────────────────────────────────

test "walkToGenesis: unresolvable predecessor returns broken fp" {
    const allocator = std.testing.allocator;

    // M1 references M0, but M0 is not in CAS (broken chain).
    const missing_fp = [_]u8{0xDE} ** 32; // arbitrary — not in CAS
    const m1_bytes = try buildTestMythosBytes(allocator, false, &missing_fp);
    defer allocator.free(m1_bytes);
    const m1_fp = blake3Hash(m1_bytes);

    var cas = TestCas.init(allocator);
    defer cas.deinit();
    try cas.put(&m1_fp, m1_bytes);
    // Note: missing_fp is intentionally NOT put in CAS.

    const result = walkToGenesis(TestCas.lookup, &cas, &m1_fp);
    switch (result) {
        .unresolvable_predecessor => |fp| {
            try std.testing.expectEqualSlices(u8, &missing_fp, &fp);
        },
        else => return error.TestUnexpectedResult,
    }
}

// ── Test (c): two genesis nodes in chain ─────────────────────────────────────

test "walkToGenesis: two genesis nodes in chain returns multiple_genesis" {
    const allocator = std.testing.allocator;

    // M0 (genesis) ← M1 (also genesis — invalid). Head = M1.
    const m0_bytes = try buildTestMythosBytes(allocator, true, null);
    defer allocator.free(m0_bytes);
    const m0_fp = blake3Hash(m0_bytes);

    // M1 claims is-genesis: true but also has a predecessor pointing at M0.
    // This is the TC18 "two-genesis-in-chain" violation.
    const m1_bytes = try buildTestMythosBytes(allocator, true, &m0_fp);
    defer allocator.free(m1_bytes);
    const m1_fp = blake3Hash(m1_bytes);

    var cas = TestCas.init(allocator);
    defer cas.deinit();
    try cas.put(&m0_fp, m0_bytes);
    try cas.put(&m1_fp, m1_bytes);

    const result = walkToGenesis(TestCas.lookup, &cas, &m1_fp);
    switch (result) {
        .multiple_genesis => |r| {
            // M1 is the first genesis seen (head side); M0 is the second (deeper).
            try std.testing.expectEqualSlices(u8, &m1_fp, &r.first);
            try std.testing.expectEqualSlices(u8, &m0_fp, &r.second);
        },
        else => return error.TestUnexpectedResult,
    }
}

// ── Test: head fp not in CAS ──────────────────────────────────────────────────

test "walkToGenesis: head fp not in CAS returns unresolvable_predecessor" {
    const allocator = std.testing.allocator;
    var cas = TestCas.init(allocator);
    defer cas.deinit();

    const phantom_fp = [_]u8{0xAB} ** 32;
    const result = walkToGenesis(TestCas.lookup, &cas, &phantom_fp);
    switch (result) {
        .unresolvable_predecessor => |fp| {
            try std.testing.expectEqualSlices(u8, &phantom_fp, &fp);
        },
        else => return error.TestUnexpectedResult,
    }
}

// ── Test: genesis-only chain (depth 1) ───────────────────────────────────────

test "walkToGenesis: genesis-only chain resolves at depth 1" {
    const allocator = std.testing.allocator;

    const m0_bytes = try buildTestMythosBytes(allocator, true, null);
    defer allocator.free(m0_bytes);
    const m0_fp = blake3Hash(m0_bytes);

    var cas = TestCas.init(allocator);
    defer cas.deinit();
    try cas.put(&m0_fp, m0_bytes);

    const result = walkToGenesis(TestCas.lookup, &cas, &m0_fp);
    switch (result) {
        .ok => |r| {
            try std.testing.expectEqualSlices(u8, &m0_fp, &r.genesis_fp);
            try std.testing.expectEqual(@as(usize, 1), r.depth);
        },
        else => return error.TestUnexpectedResult,
    }
}
