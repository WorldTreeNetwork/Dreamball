//! Encoder + decoder for the `recrypt.identity` Gordian Envelope.
//!
//! Wire format (bc-envelope dCBOR, same as Rust reference implementation):
//!
//!   tag(200)(
//!     [ tag(201)({subject_map}),
//!       map(1){ tag(201)(pred_cbor_0): tag(201)(obj_cbor_0) },
//!       map(1){ tag(201)(pred_cbor_1): tag(201)(obj_cbor_1) },
//!       ...
//!     ]
//!   )
//!
//! Assertions are sorted by SHA-256 digest:
//!   pred_digest = SHA256(pred_cbor)      -- raw CBOR, no tag wrapper
//!   obj_digest  = SHA256(obj_cbor)
//!   sort_key    = SHA256(pred_digest ++ obj_digest)
//!
//! Subject map key order (encoded-byte lex per dCBOR §2.1):
//!   "type" (4 chars), "fingerprint" (11), "format-version" (14)
//!
//! Assertion emission order (before sort): created, ed25519-public,
//! ed25519-secret, ml-dsa-public, ml-dsa-secret, name, pre-backend,
//! pre-public, pre-secret, then unknown assertions in original read order.
//! All are then sorted by assertion digest for final output.
//!
//! Interop contract: byte-identical to recrypt's Rust output for the same
//! identity content. Fixture tests in this file enforce this invariant.
//!
//! CBOR primitives come from `zbor.builder` / `zbor.DataItem`. The raw
//! byte-span preservation for unknown assertions uses `dcbor.itemLen`
//! (a thin wrapper over `zbor.advance`) so unknown predicate/object CBOR
//! is captured verbatim from the source envelope.

const std = @import("std");
const Allocator = std.mem.Allocator;
const zbor = @import("zbor");
const dcbor = @import("dcbor.zig");
const fingerprint_mod = @import("fingerprint.zig");

pub const TYPE: []const u8 = "recrypt.identity";
pub const FORMAT_VERSION: u32 = 1;

const KNOWN_PREDICATES = &[_][]const u8{
    "created",
    "ed25519-public",
    "ed25519-secret",
    "ml-dsa-public",
    "ml-dsa-secret",
    "name",
    "pre-backend",
    "pre-public",
    "pre-secret",
};

// ============================================================================
// Public types
// ============================================================================

pub const MlDsaKeyPair = struct {
    public: []const u8,
    secret: ?[]const u8,
};

pub const PreKeyMaterial = struct {
    backend: []const u8,
    public: []const u8,
    secret: ?[]const u8,
};

/// A pre-serialised predicate/object pair from an assertion that was not
/// recognised as a known predicate. Both fields are owned CBOR bytes
/// (raw, without the tag-201 wrapper).
pub const Assertion = struct {
    predicate_cbor: []const u8,
    object_cbor: []const u8,
};

pub const Identity = struct {
    fingerprint: [32]u8,
    ed25519_public: [32]u8,
    ed25519_secret: ?[32]u8 = null,
    name: ?[]const u8 = null,
    created: ?u64 = null,
    ml_dsa: ?MlDsaKeyPair = null,
    pre: ?PreKeyMaterial = null,
    unknown_assertions: []Assertion = &.{},

    /// Free every owned slice. Call with the same allocator used by `decode`.
    pub fn deinit(self: *Identity, allocator: Allocator) void {
        if (self.name) |n| allocator.free(n);
        if (self.ml_dsa) |*m| {
            allocator.free(m.public);
            if (m.secret) |s| allocator.free(s);
        }
        if (self.pre) |*p| {
            allocator.free(p.backend);
            allocator.free(p.public);
            if (p.secret) |s| allocator.free(s);
        }
        for (self.unknown_assertions) |a| {
            allocator.free(a.predicate_cbor);
            allocator.free(a.object_cbor);
        }
        if (self.unknown_assertions.len > 0) {
            allocator.free(self.unknown_assertions);
        }
    }
};

// ============================================================================
// Error set
// ============================================================================

pub const Error = error{
    FingerprintMismatch,
    WrongEnvelopeType,
    UnsupportedFormatVersion,
    MissingEd25519Public,
    InvalidCreated,
    InvalidPreKeyMaterial,
    MalformedAssertion,
    // Bubbled through from zbor / std.Io.Writer:
    Malformed,
    WriteFailed,
} || std.mem.Allocator.Error;

// ============================================================================
// Local cursor-based readers (same shape as envelope.zig).
// ============================================================================

/// Peek the major type at `cursor` without advancing.
fn peekMajor(bytes: []const u8, cursor: usize) !u3 {
    if (cursor >= bytes.len) return Error.Malformed;
    return @intCast(bytes[cursor] >> 5);
}

/// Decode one head (major + arg) and advance cursor past it. Does not consume
/// any tagged item / string content / array members.
fn readHead(bytes: []const u8, cursor: *usize) !struct { major: u3, arg: u64 } {
    if (cursor.* >= bytes.len) return Error.Malformed;
    const b = bytes[cursor.*];
    cursor.* += 1;
    const major: u3 = @intCast(b >> 5);
    const info: u5 = @intCast(b & 0x1F);
    const arg: u64 = switch (info) {
        0...23 => @as(u64, info),
        24 => blk: {
            if (cursor.* >= bytes.len) return Error.Malformed;
            const v = bytes[cursor.*];
            cursor.* += 1;
            break :blk @as(u64, v);
        },
        25 => blk: {
            if (cursor.* + 2 > bytes.len) return Error.Malformed;
            const v = std.mem.readInt(u16, bytes[cursor.*..][0..2], .big);
            cursor.* += 2;
            break :blk @as(u64, v);
        },
        26 => blk: {
            if (cursor.* + 4 > bytes.len) return Error.Malformed;
            const v = std.mem.readInt(u32, bytes[cursor.*..][0..4], .big);
            cursor.* += 4;
            break :blk @as(u64, v);
        },
        27 => blk: {
            if (cursor.* + 8 > bytes.len) return Error.Malformed;
            const v = std.mem.readInt(u64, bytes[cursor.*..][0..8], .big);
            cursor.* += 8;
            break :blk v;
        },
        else => return Error.Malformed,
    };
    return .{ .major = major, .arg = arg };
}

fn readArrayHeader(bytes: []const u8, cursor: *usize) !u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 4) return Error.MalformedAssertion;
    return h.arg;
}

fn readMapHeader(bytes: []const u8, cursor: *usize) !u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 5) return Error.MalformedAssertion;
    return h.arg;
}

fn expectTag(bytes: []const u8, cursor: *usize, want: u64) !void {
    const h = try readHead(bytes, cursor);
    if (h.major != 6) return Error.MalformedAssertion;
    if (h.arg != want) return Error.WrongEnvelopeType;
}

fn readTag(bytes: []const u8, cursor: *usize) !u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 6) return Error.MalformedAssertion;
    return h.arg;
}

fn readText(bytes: []const u8, cursor: *usize) ![]const u8 {
    const h = try readHead(bytes, cursor);
    if (h.major != 3) return Error.MalformedAssertion;
    const len: usize = @intCast(h.arg);
    if (cursor.* + len > bytes.len) return Error.Malformed;
    const s = bytes[cursor.* .. cursor.* + len];
    cursor.* += len;
    return s;
}

fn readBytesItem(bytes: []const u8, cursor: *usize) ![]const u8 {
    const h = try readHead(bytes, cursor);
    if (h.major != 2) return Error.MalformedAssertion;
    const len: usize = @intCast(h.arg);
    if (cursor.* + len > bytes.len) return Error.Malformed;
    const s = bytes[cursor.* .. cursor.* + len];
    cursor.* += len;
    return s;
}

fn readUint(bytes: []const u8, cursor: *usize) !u64 {
    const h = try readHead(bytes, cursor);
    if (h.major != 0) return Error.MalformedAssertion;
    return h.arg;
}

fn skipItem(bytes: []const u8, cursor: *usize) !void {
    if (cursor.* >= bytes.len) return Error.Malformed;
    if (zbor.advance(bytes, cursor) == null) return Error.Malformed;
}

// ============================================================================
// Assertion encoding helpers
// ============================================================================

/// One assertion ready for sort + emit.
/// `pred_cbor` and `obj_cbor` are the raw CBOR bytes (without tag-201 wrapper).
const RawAssertion = struct {
    pred_cbor: []const u8,
    obj_cbor: []const u8,
    sort_key: [32]u8, // SHA256(SHA256(pred)||SHA256(obj))

    fn computeSortKey(pred_cbor: []const u8, obj_cbor: []const u8) [32]u8 {
        var pred_hash: [32]u8 = undefined;
        var obj_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(pred_cbor, &pred_hash, .{});
        std.crypto.hash.sha2.Sha256.hash(obj_cbor, &obj_hash, .{});
        var combined: [64]u8 = undefined;
        @memcpy(combined[0..32], &pred_hash);
        @memcpy(combined[32..64], &obj_hash);
        var out: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&combined, &out, .{});
        return out;
    }
};

fn rawAssertionLt(_: void, a: RawAssertion, b: RawAssertion) bool {
    return std.mem.lessThan(u8, &a.sort_key, &b.sort_key);
}

/// Serialise `value` as CBOR text-string into an owned byte slice.
fn cborText(allocator: Allocator, value: []const u8) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    try zbor.builder.writeTextString(&ai.writer, value);
    return ai.toOwnedSlice();
}

/// Serialise `value` as CBOR byte-string into an owned byte slice.
fn cborBytes(allocator: Allocator, value: []const u8) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    try zbor.builder.writeByteString(&ai.writer, value);
    return ai.toOwnedSlice();
}

// ============================================================================
// encode
// ============================================================================

/// Encode an `Identity` as a `recrypt.identity` Gordian Envelope.
/// Validates `fingerprint == Blake3(ed25519_public)`.
/// Returns owned bytes; caller frees with `allocator.free`.
pub fn encode(allocator: Allocator, identity: Identity) ![]u8 {
    // Validate fingerprint
    const fp = fingerprint_mod.Fingerprint.fromEd25519(identity.ed25519_public);
    if (!std.mem.eql(u8, &fp.bytes, &identity.fingerprint)) {
        return Error.FingerprintMismatch;
    }

    // Build subject map: type, fingerprint, format-version (sorted by encoded-key lex)
    var subj = dcbor.PairList.init(allocator);
    defer subj.deinit();
    try subj.addText("type", TYPE);
    try subj.addBytes("fingerprint", &identity.fingerprint);
    try subj.addUint("format-version", FORMAT_VERSION);
    subj.sort(); // sorts: "type"(4) < "fingerprint"(11) < "format-version"(14)

    // Encode subject map CBOR
    var subj_ai = std.Io.Writer.Allocating.init(allocator);
    defer subj_ai.deinit();
    try zbor.builder.writeMap(&subj_ai.writer, subj.pairs.items.len);
    for (subj.pairs.items) |p| {
        try zbor.builder.writeTextString(&subj_ai.writer, p.key);
        try subj_ai.writer.writeAll(p.value);
    }
    const subj_map_cbor = subj_ai.written();

    // Collect all assertions (in emission order, then sort by digest)
    var assertions: std.ArrayListUnmanaged(RawAssertion) = .empty;
    defer {
        for (assertions.items) |a| {
            allocator.free(a.pred_cbor);
            allocator.free(a.obj_cbor);
        }
        assertions.deinit(allocator);
    }

    // Helper to append a text-pred / bytes-obj assertion
    const appendBytesAssertion = struct {
        fn run(alloc: Allocator, list: *std.ArrayListUnmanaged(RawAssertion), pred: []const u8, obj_bytes: []const u8) !void {
            const pred_cbor = try cborText(alloc, pred);
            errdefer alloc.free(pred_cbor);
            const obj_cbor = try cborBytes(alloc, obj_bytes);
            errdefer alloc.free(obj_cbor);
            const sk = RawAssertion.computeSortKey(pred_cbor, obj_cbor);
            try list.append(alloc, .{ .pred_cbor = pred_cbor, .obj_cbor = obj_cbor, .sort_key = sk });
        }
    }.run;

    const appendTextAssertion = struct {
        fn run(alloc: Allocator, list: *std.ArrayListUnmanaged(RawAssertion), pred: []const u8, obj_text: []const u8) !void {
            const pred_cbor = try cborText(alloc, pred);
            errdefer alloc.free(pred_cbor);
            const obj_cbor = try cborText(alloc, obj_text);
            errdefer alloc.free(obj_cbor);
            const sk = RawAssertion.computeSortKey(pred_cbor, obj_cbor);
            try list.append(alloc, .{ .pred_cbor = pred_cbor, .obj_cbor = obj_cbor, .sort_key = sk });
        }
    }.run;

    // 1. created (tag 1 + uint)
    if (identity.created) |ts| {
        const pred_cbor = try cborText(allocator, "created");
        errdefer allocator.free(pred_cbor);

        var ow = std.Io.Writer.Allocating.init(allocator);
        errdefer ow.deinit();
        try zbor.builder.writeTag(&ow.writer, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(&ow.writer, @intCast(ts));
        const obj_cbor = try ow.toOwnedSlice();
        errdefer allocator.free(obj_cbor);

        const sk = RawAssertion.computeSortKey(pred_cbor, obj_cbor);
        try assertions.append(allocator, .{ .pred_cbor = pred_cbor, .obj_cbor = obj_cbor, .sort_key = sk });
    }

    // 2. ed25519-public (always present)
    try appendBytesAssertion(allocator, &assertions, "ed25519-public", &identity.ed25519_public);

    // 3. ed25519-secret (if present)
    if (identity.ed25519_secret) |sec| {
        try appendBytesAssertion(allocator, &assertions, "ed25519-secret", &sec);
    }

    // 4. ml-dsa-public (if present)
    if (identity.ml_dsa) |ml| {
        try appendBytesAssertion(allocator, &assertions, "ml-dsa-public", ml.public);
        // 5. ml-dsa-secret (if present)
        if (ml.secret) |sec| {
            try appendBytesAssertion(allocator, &assertions, "ml-dsa-secret", sec);
        }
    }

    // 6. name (if present)
    if (identity.name) |n| {
        try appendTextAssertion(allocator, &assertions, "name", n);
    }

    // 7-9. pre-backend, pre-public, pre-secret (if present)
    if (identity.pre) |pre| {
        try appendTextAssertion(allocator, &assertions, "pre-backend", pre.backend);
        try appendBytesAssertion(allocator, &assertions, "pre-public", pre.public);
        if (pre.secret) |sec| {
            try appendBytesAssertion(allocator, &assertions, "pre-secret", sec);
        }
    }

    // 10. Unknown assertions (already have pre-serialised pred/obj CBOR)
    for (identity.unknown_assertions) |ua| {
        const pred_cbor = try allocator.dupe(u8, ua.predicate_cbor);
        const obj_cbor = try allocator.dupe(u8, ua.object_cbor);
        const sk = RawAssertion.computeSortKey(pred_cbor, obj_cbor);
        try assertions.append(allocator, .{ .pred_cbor = pred_cbor, .obj_cbor = obj_cbor, .sort_key = sk });
    }

    // Sort all assertions by their digest key
    std.sort.insertion(RawAssertion, assertions.items, {}, rawAssertionLt);

    // Emit: tag(200) [ tag(201)(subj_map), assertion_map_0, ..., assertion_map_N ]
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    const ow = &out.writer;

    try zbor.builder.writeTag(ow, dcbor.Tag.envelope); // tag 200

    const total_elements = 1 + assertions.items.len;
    try zbor.builder.writeArray(ow, total_elements);

    // Subject: tag(201)(map)
    try zbor.builder.writeTag(ow, dcbor.Tag.leaf); // tag 201
    try ow.writeAll(subj_map_cbor);

    // Each assertion: map(1){ tag201(pred): tag201(obj) }
    for (assertions.items) |a| {
        try zbor.builder.writeMap(ow, 1);
        try zbor.builder.writeTag(ow, dcbor.Tag.leaf);
        try ow.writeAll(a.pred_cbor);
        try zbor.builder.writeTag(ow, dcbor.Tag.leaf);
        try ow.writeAll(a.obj_cbor);
    }

    return out.toOwnedSlice();
}

// ============================================================================
// decode
// ============================================================================

/// Decode a `recrypt.identity` Gordian Envelope.
/// Validates `fingerprint == Blake3(ed25519_public)`.
/// All owned fields use `allocator.dupe` so the input bytes can be freed.
/// Caller must call `identity.deinit(allocator)` when done.
pub fn decode(allocator: Allocator, bytes: []const u8) !Identity {
    var cursor: usize = 0;

    // tag(200)
    const first_tag = try readTag(bytes, &cursor);
    if (first_tag != dcbor.Tag.envelope) return Error.WrongEnvelopeType;

    // Must be an array (subject + 0 or more assertions)
    const array_len = try readArrayHeader(bytes, &cursor);
    if (array_len == 0) return Error.MalformedAssertion;

    // Subject: tag(201)(map{...})
    const second_tag = try readTag(bytes, &cursor);
    if (second_tag != dcbor.Tag.leaf) return Error.MalformedAssertion;

    // Parse the subject map
    const map_len = try readMapHeader(bytes, &cursor);

    var parsed_type: ?[]const u8 = null;
    var parsed_version: ?u64 = null;
    var parsed_fingerprint: ?[32]u8 = null;

    var mi: u64 = 0;
    while (mi < map_len) : (mi += 1) {
        const key = try readText(bytes, &cursor);
        if (std.mem.eql(u8, key, "type")) {
            parsed_type = try readText(bytes, &cursor);
        } else if (std.mem.eql(u8, key, "format-version")) {
            parsed_version = try readUint(bytes, &cursor);
        } else if (std.mem.eql(u8, key, "fingerprint")) {
            const fp_bytes = try readBytesItem(bytes, &cursor);
            if (fp_bytes.len != 32) return Error.MalformedAssertion;
            var arr: [32]u8 = undefined;
            @memcpy(&arr, fp_bytes);
            parsed_fingerprint = arr;
        } else {
            // Unknown subject key — skip the value
            try skipItem(bytes, &cursor);
        }
    }

    // Validate type
    const ty = parsed_type orelse return Error.WrongEnvelopeType;
    if (!std.mem.eql(u8, ty, TYPE)) return Error.WrongEnvelopeType;

    // Validate format-version
    const version = parsed_version orelse return Error.UnsupportedFormatVersion;
    if (version != FORMAT_VERSION) return Error.UnsupportedFormatVersion;

    // Fingerprint
    const fp_arr = parsed_fingerprint orelse return Error.MalformedAssertion;

    // Walk assertion elements (array_len - 1 assertions)
    var ed25519_public: ?[32]u8 = null;
    var ed25519_secret: ?[32]u8 = null;
    var name: ?[]const u8 = null;
    var created: ?u64 = null;
    var ml_dsa_public: ?[]const u8 = null;
    var ml_dsa_secret: ?[]const u8 = null;
    var pre_backend: ?[]const u8 = null;
    var pre_public: ?[]const u8 = null;
    var pre_secret: ?[]const u8 = null;
    var unknown_list: std.ArrayListUnmanaged(Assertion) = .empty;
    errdefer {
        for (unknown_list.items) |ua| {
            allocator.free(ua.predicate_cbor);
            allocator.free(ua.object_cbor);
        }
        unknown_list.deinit(allocator);
    }

    // Also track allocated fields for cleanup on error
    var alloc_name: ?[]const u8 = null;
    var alloc_ml_dsa_public: ?[]const u8 = null;
    var alloc_ml_dsa_secret: ?[]const u8 = null;
    var alloc_pre_backend: ?[]const u8 = null;
    var alloc_pre_public: ?[]const u8 = null;
    var alloc_pre_secret: ?[]const u8 = null;

    errdefer {
        if (alloc_name) |s| allocator.free(s);
        if (alloc_ml_dsa_public) |s| allocator.free(s);
        if (alloc_ml_dsa_secret) |s| allocator.free(s);
        if (alloc_pre_backend) |s| allocator.free(s);
        if (alloc_pre_public) |s| allocator.free(s);
        if (alloc_pre_secret) |s| allocator.free(s);
    }

    var ai: u64 = 1;
    while (ai < array_len) : (ai += 1) {
        // Each element is a map(1){ tag201(pred): tag201(obj) }
        const m_len = try readMapHeader(bytes, &cursor);
        if (m_len != 1) return Error.MalformedAssertion;

        // key = tag201(pred_cbor)
        const pred_tag = try readTag(bytes, &cursor);
        if (pred_tag != dcbor.Tag.leaf) return Error.MalformedAssertion;
        // Record pred_cbor start/end for unknown assertion preservation
        const pred_start = cursor;
        const pred_text = try readText(bytes, &cursor);
        const pred_end = cursor;

        // value = tag201(obj_cbor)
        const obj_tag = try readTag(bytes, &cursor);
        if (obj_tag != dcbor.Tag.leaf) return Error.MalformedAssertion;
        // Start of the obj CBOR — captured only when we fall through to the
        // unknown-predicate branch below; the known branches advance
        // `cursor` themselves.
        const obj_start = cursor;

        if (std.mem.eql(u8, pred_text, "ed25519-public")) {
            const b = try readBytesItem(bytes, &cursor);
            if (b.len != 32) return Error.MalformedAssertion;
            var arr: [32]u8 = undefined;
            @memcpy(&arr, b);
            ed25519_public = arr;
        } else if (std.mem.eql(u8, pred_text, "ed25519-secret")) {
            const b = try readBytesItem(bytes, &cursor);
            if (b.len != 32) return Error.MalformedAssertion;
            var arr: [32]u8 = undefined;
            @memcpy(&arr, b);
            ed25519_secret = arr;
        } else if (std.mem.eql(u8, pred_text, "ml-dsa-public")) {
            const b = try readBytesItem(bytes, &cursor);
            const owned = try allocator.dupe(u8, b);
            alloc_ml_dsa_public = owned;
            ml_dsa_public = owned;
        } else if (std.mem.eql(u8, pred_text, "ml-dsa-secret")) {
            const b = try readBytesItem(bytes, &cursor);
            const owned = try allocator.dupe(u8, b);
            alloc_ml_dsa_secret = owned;
            ml_dsa_secret = owned;
        } else if (std.mem.eql(u8, pred_text, "name")) {
            const t = try readText(bytes, &cursor);
            const owned = try allocator.dupe(u8, t);
            alloc_name = owned;
            name = owned;
        } else if (std.mem.eql(u8, pred_text, "created")) {
            // Must be tag(1)(uint)
            const tag_val = try readTag(bytes, &cursor);
            if (tag_val != dcbor.Tag.epoch_time) return Error.InvalidCreated;
            const ts = try readUint(bytes, &cursor);
            created = ts;
        } else if (std.mem.eql(u8, pred_text, "pre-backend")) {
            const t = try readText(bytes, &cursor);
            const owned = try allocator.dupe(u8, t);
            alloc_pre_backend = owned;
            pre_backend = owned;
        } else if (std.mem.eql(u8, pred_text, "pre-public")) {
            const b = try readBytesItem(bytes, &cursor);
            const owned = try allocator.dupe(u8, b);
            alloc_pre_public = owned;
            pre_public = owned;
        } else if (std.mem.eql(u8, pred_text, "pre-secret")) {
            const b = try readBytesItem(bytes, &cursor);
            const owned = try allocator.dupe(u8, b);
            alloc_pre_secret = owned;
            pre_secret = owned;
        } else {
            // Unknown assertion: preserve raw CBOR bytes of pred and obj
            const pred_raw = try allocator.dupe(u8, bytes[pred_start..pred_end]);
            // Skip the object and capture its extent
            try skipItem(bytes, &cursor);
            const obj_end = cursor;
            const obj_raw = try allocator.dupe(u8, bytes[obj_start..obj_end]);
            try unknown_list.append(allocator, .{ .predicate_cbor = pred_raw, .object_cbor = obj_raw });
            // Object already skipped — continue to next assertion
            continue;
        }
    }

    // Require ed25519-public
    const ed25519_pub = ed25519_public orelse return Error.MissingEd25519Public;

    // Validate fingerprint
    const expected_fp = fingerprint_mod.Fingerprint.fromEd25519(ed25519_pub);
    if (!std.mem.eql(u8, &expected_fp.bytes, &fp_arr)) {
        return Error.FingerprintMismatch;
    }

    // Validate PRE key material consistency
    if (pre_backend != null and pre_public == null) return Error.InvalidPreKeyMaterial;
    if (pre_public != null and pre_backend == null) return Error.InvalidPreKeyMaterial;

    // Build ml_dsa optional
    const ml_dsa: ?MlDsaKeyPair = if (ml_dsa_public) |pub_key|
        .{ .public = pub_key, .secret = ml_dsa_secret }
    else blk: {
        // If ml_dsa_secret present without public, ignore (or we could error; be lenient)
        break :blk null;
    };

    // Build pre optional
    const pre: ?PreKeyMaterial = if (pre_backend) |backend|
        .{ .backend = backend, .public = pre_public.?, .secret = pre_secret }
    else
        null;

    const unknown_slice = try unknown_list.toOwnedSlice(allocator);

    // Suppress unused-variable warnings for alloc_* that are now owned by Identity
    alloc_name = null;
    alloc_ml_dsa_public = null;
    alloc_ml_dsa_secret = null;
    alloc_pre_backend = null;
    alloc_pre_public = null;
    alloc_pre_secret = null;

    return Identity{
        .fingerprint = fp_arr,
        .ed25519_public = ed25519_pub,
        .ed25519_secret = ed25519_secret,
        .name = name,
        .created = created,
        .ml_dsa = ml_dsa,
        .pre = pre,
        .unknown_assertions = unknown_slice,
    };
}

// ============================================================================
// Tests
// ============================================================================

fn makeIdentity(pk: [32]u8) Identity {
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);
    return .{
        .fingerprint = fp.bytes,
        .ed25519_public = pk,
    };
}

test "encode → decode round-trips ed25519-only identity" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x01} ** 32;
    const id = makeIdentity(pk);

    const bytes = try encode(allocator, id);
    defer allocator.free(bytes);

    var decoded = try decode(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &id.fingerprint, &decoded.fingerprint);
    try std.testing.expectEqualSlices(u8, &id.ed25519_public, &decoded.ed25519_public);
    try std.testing.expect(decoded.ed25519_secret == null);
    try std.testing.expect(decoded.ml_dsa == null);
    try std.testing.expect(decoded.pre == null);
    try std.testing.expect(decoded.name == null);
    try std.testing.expect(decoded.created == null);
    try std.testing.expectEqual(@as(usize, 0), decoded.unknown_assertions.len);
}

test "encode → decode round-trips hybrid (ed25519 + ml-dsa, no pre)" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x02} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);
    const ml_pub = [_]u8{0xAA} ** 64;
    const ml_sec = [_]u8{0xBB} ** 32;

    const id = Identity{
        .fingerprint = fp.bytes,
        .ed25519_public = pk,
        .ml_dsa = .{ .public = &ml_pub, .secret = &ml_sec },
    };

    const bytes = try encode(allocator, id);
    defer allocator.free(bytes);

    var decoded = try decode(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &pk, &decoded.ed25519_public);
    try std.testing.expect(decoded.ml_dsa != null);
    try std.testing.expectEqualSlices(u8, &ml_pub, decoded.ml_dsa.?.public);
    try std.testing.expectEqualSlices(u8, &ml_sec, decoded.ml_dsa.?.secret.?);
    try std.testing.expect(decoded.pre == null);
}

test "encode → decode round-trips full identity" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x03} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);
    const sk: [32]u8 = [_]u8{0x04} ** 32;
    const ml_pub = [_]u8{0xAA} ** 128;
    const ml_sec = [_]u8{0xBB} ** 64;
    const pre_pub = [_]u8{0xCC} ** 32;
    const pre_sec = [_]u8{0xDD} ** 32;

    const id = Identity{
        .fingerprint = fp.bytes,
        .ed25519_public = pk,
        .ed25519_secret = sk,
        .name = "test-identity",
        .created = 1700000000,
        .ml_dsa = .{ .public = &ml_pub, .secret = &ml_sec },
        .pre = .{ .backend = "lattice-bfv", .public = &pre_pub, .secret = &pre_sec },
    };

    const bytes = try encode(allocator, id);
    defer allocator.free(bytes);

    var decoded = try decode(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqualSlices(u8, &pk, &decoded.ed25519_public);
    try std.testing.expectEqualSlices(u8, &sk, &decoded.ed25519_secret.?);
    try std.testing.expectEqualStrings("test-identity", decoded.name.?);
    try std.testing.expectEqual(@as(u64, 1700000000), decoded.created.?);
    try std.testing.expect(decoded.ml_dsa != null);
    try std.testing.expectEqualSlices(u8, &ml_pub, decoded.ml_dsa.?.public);
    try std.testing.expect(decoded.pre != null);
    try std.testing.expectEqualStrings("lattice-bfv", decoded.pre.?.backend);
    try std.testing.expectEqualSlices(u8, &pre_pub, decoded.pre.?.public);
    try std.testing.expectEqualSlices(u8, &pre_sec, decoded.pre.?.secret.?);
}

test "encode → decode preserves two unknown assertions in order" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x05} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);

    // Build raw CBOR for two unknown assertions
    const pred1 = try cborText(allocator, "zzz-unknown-first");
    defer allocator.free(pred1);

    const obj1 = try cborBytes(allocator, &[_]u8{ 0xDE, 0xAD });
    defer allocator.free(obj1);

    const pred2 = try cborText(allocator, "aaa-unknown-second");
    defer allocator.free(pred2);

    const obj2 = try cborBytes(allocator, &[_]u8{ 0xBE, 0xEF });
    defer allocator.free(obj2);

    const unknowns = [_]Assertion{
        .{ .predicate_cbor = pred1, .object_cbor = obj1 },
        .{ .predicate_cbor = pred2, .object_cbor = obj2 },
    };

    const id = Identity{
        .fingerprint = fp.bytes,
        .ed25519_public = pk,
        .unknown_assertions = @constCast(&unknowns),
    };

    const bytes = try encode(allocator, id);
    defer allocator.free(bytes);

    // Re-encode — must be byte-identical
    const bytes2 = try encode(allocator, id);
    defer allocator.free(bytes2);
    try std.testing.expectEqualSlices(u8, bytes, bytes2);

    // Decode and verify we get 2 unknown assertions
    var decoded = try decode(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), decoded.unknown_assertions.len);

    // Re-encode decoded — must be byte-identical to original
    const fp_decoded = fingerprint_mod.Fingerprint.fromEd25519(decoded.ed25519_public);
    var decoded_for_encode = decoded;
    decoded_for_encode.fingerprint = fp_decoded.bytes;
    const bytes3 = try encode(allocator, decoded_for_encode);
    defer allocator.free(bytes3);
    try std.testing.expectEqualSlices(u8, bytes, bytes3);
}

test "decode rejects fingerprint mismatch" {
    const allocator = std.testing.allocator;

    // Hand-build an envelope with a wrong fingerprint.
    // subject map: type="recrypt.identity", fingerprint=<wrong 32 bytes>, format-version=1
    const pk: [32]u8 = [_]u8{0x10} ** 32;
    const wrong_fp: [32]u8 = [_]u8{0xFF} ** 32;

    var subj_ai = std.Io.Writer.Allocating.init(allocator);
    defer subj_ai.deinit();
    try zbor.builder.writeMap(&subj_ai.writer, 3);
    try zbor.builder.writeTextString(&subj_ai.writer, "type");
    try zbor.builder.writeTextString(&subj_ai.writer, TYPE);
    try zbor.builder.writeTextString(&subj_ai.writer, "fingerprint");
    try zbor.builder.writeByteString(&subj_ai.writer, &wrong_fp);
    try zbor.builder.writeTextString(&subj_ai.writer, "format-version");
    try zbor.builder.writeInt(&subj_ai.writer, FORMAT_VERSION);
    const subj_cbor = subj_ai.written();

    // Build assertion for ed25519-public
    const pred_cbor = try cborText(allocator, "ed25519-public");
    defer allocator.free(pred_cbor);

    const obj_cbor = try cborBytes(allocator, &pk);
    defer allocator.free(obj_cbor);

    var env_ai = std.Io.Writer.Allocating.init(allocator);
    defer env_ai.deinit();
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.envelope);
    try zbor.builder.writeArray(&env_ai.writer, 2);
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.leaf);
    try env_ai.writer.writeAll(subj_cbor);
    try zbor.builder.writeMap(&env_ai.writer, 1);
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.leaf);
    try env_ai.writer.writeAll(pred_cbor);
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.leaf);
    try env_ai.writer.writeAll(obj_cbor);
    const env_bytes = env_ai.written();

    try std.testing.expectError(Error.FingerprintMismatch, decode(allocator, env_bytes));
}

test "decode rejects missing ed25519-public" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x20} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);

    // Build valid subject map but NO ed25519-public assertion
    var subj_ai = std.Io.Writer.Allocating.init(allocator);
    defer subj_ai.deinit();
    try zbor.builder.writeMap(&subj_ai.writer, 3);
    try zbor.builder.writeTextString(&subj_ai.writer, "type");
    try zbor.builder.writeTextString(&subj_ai.writer, TYPE);
    try zbor.builder.writeTextString(&subj_ai.writer, "fingerprint");
    try zbor.builder.writeByteString(&subj_ai.writer, &fp.bytes);
    try zbor.builder.writeTextString(&subj_ai.writer, "format-version");
    try zbor.builder.writeInt(&subj_ai.writer, FORMAT_VERSION);
    const subj_cbor = subj_ai.written();

    // Envelope with only subject (array of 1)
    var env_ai = std.Io.Writer.Allocating.init(allocator);
    defer env_ai.deinit();
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.envelope);
    try zbor.builder.writeArray(&env_ai.writer, 1);
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.leaf);
    try env_ai.writer.writeAll(subj_cbor);
    const env_bytes = env_ai.written();

    try std.testing.expectError(Error.MissingEd25519Public, decode(allocator, env_bytes));
}

test "decode rejects wrong type string" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x30} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);

    var subj_ai = std.Io.Writer.Allocating.init(allocator);
    defer subj_ai.deinit();
    try zbor.builder.writeMap(&subj_ai.writer, 3);
    try zbor.builder.writeTextString(&subj_ai.writer, "type");
    try zbor.builder.writeTextString(&subj_ai.writer, "wrong.type");
    try zbor.builder.writeTextString(&subj_ai.writer, "fingerprint");
    try zbor.builder.writeByteString(&subj_ai.writer, &fp.bytes);
    try zbor.builder.writeTextString(&subj_ai.writer, "format-version");
    try zbor.builder.writeInt(&subj_ai.writer, FORMAT_VERSION);
    const subj_cbor = subj_ai.written();

    var env_ai = std.Io.Writer.Allocating.init(allocator);
    defer env_ai.deinit();
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.envelope);
    try zbor.builder.writeArray(&env_ai.writer, 1);
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.leaf);
    try env_ai.writer.writeAll(subj_cbor);
    const env_bytes = env_ai.written();

    try std.testing.expectError(Error.WrongEnvelopeType, decode(allocator, env_bytes));
}

test "decode rejects wrong format-version" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x40} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);

    var subj_ai = std.Io.Writer.Allocating.init(allocator);
    defer subj_ai.deinit();
    try zbor.builder.writeMap(&subj_ai.writer, 3);
    try zbor.builder.writeTextString(&subj_ai.writer, "type");
    try zbor.builder.writeTextString(&subj_ai.writer, TYPE);
    try zbor.builder.writeTextString(&subj_ai.writer, "fingerprint");
    try zbor.builder.writeByteString(&subj_ai.writer, &fp.bytes);
    try zbor.builder.writeTextString(&subj_ai.writer, "format-version");
    try zbor.builder.writeInt(&subj_ai.writer, 99);
    const subj_cbor = subj_ai.written();

    var env_ai = std.Io.Writer.Allocating.init(allocator);
    defer env_ai.deinit();
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.envelope);
    try zbor.builder.writeArray(&env_ai.writer, 1);
    try zbor.builder.writeTag(&env_ai.writer, dcbor.Tag.leaf);
    try env_ai.writer.writeAll(subj_cbor);
    const env_bytes = env_ai.written();

    try std.testing.expectError(Error.UnsupportedFormatVersion, decode(allocator, env_bytes));
}

// ============================================================================
// Fixture tests — byte-identical interop with recrypt Rust output
// ============================================================================

test "fixture: ed25519-only round-trips byte-identically" {
    const allocator = std.testing.allocator;

    const fixture = @embedFile("recrypt-identity-fixtures/identity-ed25519-only.envelope");
    try std.testing.expectEqual(@as(usize, 144), fixture.len);

    var decoded = try decode(allocator, fixture);
    defer decoded.deinit(allocator);

    // Sanity: fingerprint hex from JSON sidecar
    const expected_fp_hex = "4a78877c4a0926fc5d5cb282bb45c11c8489b202fe1890fa0c6593e6192b9f75";
    var expected_fp: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_fp, expected_fp_hex);
    try std.testing.expectEqualSlices(u8, &expected_fp, &decoded.fingerprint);

    // Re-encode and compare
    const reemitted = try encode(allocator, decoded);
    defer allocator.free(reemitted);
    try std.testing.expectEqualSlices(u8, fixture, reemitted);
}

test "fixture: hybrid-no-pre round-trips byte-identically" {
    const allocator = std.testing.allocator;

    const fixture = @embedFile("recrypt-identity-fixtures/identity-hybrid-no-pre.envelope");
    try std.testing.expectEqual(@as(usize, 7803), fixture.len);

    var decoded = try decode(allocator, fixture);
    defer decoded.deinit(allocator);

    // Fingerprint from JSON sidecar
    const expected_fp_hex = "34a374a71ce45a64cef46deae14583ab4a1754f8e3539b44f346c813844851c3";
    var expected_fp: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_fp, expected_fp_hex);
    try std.testing.expectEqualSlices(u8, &expected_fp, &decoded.fingerprint);

    // Re-encode and compare
    const reemitted = try encode(allocator, decoded);
    defer allocator.free(reemitted);
    try std.testing.expectEqualSlices(u8, fixture, reemitted);
}

test "fixture: full identity round-trips byte-identically" {
    const allocator = std.testing.allocator;

    const fixture = @embedFile("recrypt-identity-fixtures/identity-full.envelope");
    try std.testing.expectEqual(@as(usize, 7958), fixture.len);

    var decoded = try decode(allocator, fixture);
    defer decoded.deinit(allocator);

    // Fingerprint from JSON sidecar
    const expected_fp_hex = "af3da09f0f0b45c64f3259fb3870249e810be4383c4c5c89eeeb5f14a2723e51";
    var expected_fp: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_fp, expected_fp_hex);
    try std.testing.expectEqualSlices(u8, &expected_fp, &decoded.fingerprint);

    // Re-encode and compare
    const reemitted = try encode(allocator, decoded);
    defer allocator.free(reemitted);
    try std.testing.expectEqualSlices(u8, fixture, reemitted);
}

test "fixture: hybrid-no-pre preserves dreamball-lineage unknown assertion" {
    const allocator = std.testing.allocator;

    const fixture = @embedFile("recrypt-identity-fixtures/identity-hybrid-no-pre.envelope");

    var decoded = try decode(allocator, fixture);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.unknown_assertions.len);

    // The predicate CBOR should be text("dreamball-lineage")
    const ua = decoded.unknown_assertions[0];
    const di = try zbor.DataItem.new(ua.predicate_cbor);
    const pred_text = di.string() orelse return error.NotAString;
    try std.testing.expectEqualStrings("dreamball-lineage", pred_text);

    // Re-encode and verify byte-identical
    const reemitted = try encode(allocator, decoded);
    defer allocator.free(reemitted);
    try std.testing.expectEqualSlices(u8, fixture, reemitted);
}
