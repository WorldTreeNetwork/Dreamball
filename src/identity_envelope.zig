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

const std = @import("std");
const Allocator = std.mem.Allocator;
const cbor = @import("cbor.zig");
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
} || cbor.Error || std.mem.Allocator.Error;

// ============================================================================
// Pair / PairList helpers (copied from envelope.zig — no refactor per plan §4)
// ============================================================================

/// A pre-serialised key-value pair for building subject maps.
/// `key` is a plain string; `value` is owned dCBOR bytes for the value only.
const Pair = struct { key: []const u8, value: []const u8 };

fn pairLt(_: void, a: Pair, b: Pair) bool {
    if (a.key.len != b.key.len) return a.key.len < b.key.len;
    return std.mem.lessThan(u8, a.key, b.key);
}

const PairList = struct {
    pairs: std.ArrayListUnmanaged(Pair) = .empty,
    allocator: Allocator,

    fn init(allocator: Allocator) PairList {
        return .{ .pairs = .empty, .allocator = allocator };
    }

    fn deinit(self: *PairList) void {
        for (self.pairs.items) |p| {
            self.allocator.free(p.key);
            self.allocator.free(p.value);
        }
        self.pairs.deinit(self.allocator);
    }

    fn addOwned(self: *PairList, key: []const u8, value: []u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        try self.pairs.append(self.allocator, .{ .key = key_copy, .value = value });
    }

    fn addText(self: *PairList, key: []const u8, text: []const u8) !void {
        var w = cbor.Writer.init(self.allocator);
        errdefer w.deinit();
        try w.writeText(text);
        const bytes = try w.toOwned();
        try self.addOwned(key, bytes);
    }

    fn addUint(self: *PairList, key: []const u8, v: u64) !void {
        var w = cbor.Writer.init(self.allocator);
        errdefer w.deinit();
        try w.writeUint(v);
        const bytes = try w.toOwned();
        try self.addOwned(key, bytes);
    }

    fn addBytes(self: *PairList, key: []const u8, b: []const u8) !void {
        var w = cbor.Writer.init(self.allocator);
        errdefer w.deinit();
        try w.writeBytes(b);
        const raw = try w.toOwned();
        try self.addOwned(key, raw);
    }

    fn sort(self: *PairList) void {
        std.sort.insertion(Pair, self.pairs.items, {}, pairLt);
    }
};

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

/// Build a single-key CBOR map wrapping two tag-201 leaves:
///   map(1){ tag(201)(pred_cbor): tag(201)(obj_cbor) }
/// Returns owned bytes.
fn encodeAssertionMap(allocator: Allocator, pred_cbor: []const u8, obj_cbor: []const u8) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();
    try w.writeMapHeader(1);
    try w.writeTag(cbor.Tag.leaf); // tag 201
    try w.appendSlice(pred_cbor);
    try w.writeTag(cbor.Tag.leaf); // tag 201
    try w.appendSlice(obj_cbor);
    return w.toOwned();
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
    var subj = PairList.init(allocator);
    defer subj.deinit();
    try subj.addText("type", TYPE);
    try subj.addBytes("fingerprint", &identity.fingerprint);
    try subj.addUint("format-version", FORMAT_VERSION);
    subj.sort(); // sorts: "type"(4) < "fingerprint"(11) < "format-version"(14)

    // Encode subject map CBOR
    var subj_writer = cbor.Writer.init(allocator);
    defer subj_writer.deinit();
    try subj_writer.writeMapHeader(subj.pairs.items.len);
    for (subj.pairs.items) |p| {
        try subj_writer.writeText(p.key);
        try subj_writer.appendSlice(p.value);
    }
    const subj_map_cbor = try subj_writer.toOwned();
    defer allocator.free(subj_map_cbor);

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
            var pw = cbor.Writer.init(alloc);
            defer pw.deinit();
            try pw.writeText(pred);
            const pred_cbor = try pw.toOwned();

            var ow = cbor.Writer.init(alloc);
            defer ow.deinit();
            try ow.writeBytes(obj_bytes);
            const obj_cbor = try ow.toOwned();

            const sk = RawAssertion.computeSortKey(pred_cbor, obj_cbor);
            try list.append(alloc, .{ .pred_cbor = pred_cbor, .obj_cbor = obj_cbor, .sort_key = sk });
        }
    }.run;

    const appendTextAssertion = struct {
        fn run(alloc: Allocator, list: *std.ArrayListUnmanaged(RawAssertion), pred: []const u8, obj_text: []const u8) !void {
            var pw = cbor.Writer.init(alloc);
            defer pw.deinit();
            try pw.writeText(pred);
            const pred_cbor = try pw.toOwned();

            var ow = cbor.Writer.init(alloc);
            defer ow.deinit();
            try ow.writeText(obj_text);
            const obj_cbor = try ow.toOwned();

            const sk = RawAssertion.computeSortKey(pred_cbor, obj_cbor);
            try list.append(alloc, .{ .pred_cbor = pred_cbor, .obj_cbor = obj_cbor, .sort_key = sk });
        }
    }.run;

    // 1. created (tag 1 + uint)
    if (identity.created) |ts| {
        var pw = cbor.Writer.init(allocator);
        defer pw.deinit();
        try pw.writeText("created");
        const pred_cbor = try pw.toOwned();

        var ow = cbor.Writer.init(allocator);
        defer ow.deinit();
        try ow.writeTag(cbor.Tag.epoch_time);
        try ow.writeUint(ts);
        const obj_cbor = try ow.toOwned();

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
    var out = cbor.Writer.init(allocator);
    errdefer out.deinit();

    try out.writeTag(cbor.Tag.envelope); // tag 200

    const total_elements = 1 + assertions.items.len;
    try out.writeArrayHeader(total_elements);

    // Subject: tag(201)(map)
    try out.writeTag(cbor.Tag.leaf); // tag 201
    try out.appendSlice(subj_map_cbor);

    // Each assertion: map(1){ tag201(pred): tag201(obj) }
    for (assertions.items) |a| {
        try out.writeMapHeader(1);
        try out.writeTag(cbor.Tag.leaf);
        try out.appendSlice(a.pred_cbor);
        try out.writeTag(cbor.Tag.leaf);
        try out.appendSlice(a.obj_cbor);
    }

    return out.toOwned();
}

// ============================================================================
// Skip helpers for decode
// ============================================================================

/// Skip one complete CBOR item starting at reader's current position.
fn skipItem(r: *cbor.Reader) !void {
    try r.skipItem();
}

// ============================================================================
// decode
// ============================================================================

/// Decode a `recrypt.identity` Gordian Envelope.
/// Validates `fingerprint == Blake3(ed25519_public)`.
/// All owned fields use `allocator.dupe` so the input bytes can be freed.
/// Caller must call `identity.deinit(allocator)` when done.
pub fn decode(allocator: Allocator, bytes: []const u8) !Identity {
    var r = cbor.Reader.init(bytes);

    // tag(200)
    try r.expectTag(cbor.Tag.envelope);

    // Must be an array (subject + 0 or more assertions)
    const array_len = try r.readArrayHeader();
    if (array_len == 0) return Error.MalformedAssertion;

    // Subject: tag(201)(map{...})
    try r.expectTag(cbor.Tag.leaf);

    // Parse the subject map
    const map_len = try r.readMapHeader();

    var parsed_type: ?[]const u8 = null;
    var parsed_version: ?u64 = null;
    var parsed_fingerprint: ?[32]u8 = null;

    var mi: u64 = 0;
    while (mi < map_len) : (mi += 1) {
        const key = try r.readText();
        if (std.mem.eql(u8, key, "type")) {
            parsed_type = try r.readText();
        } else if (std.mem.eql(u8, key, "format-version")) {
            parsed_version = try r.readUint();
        } else if (std.mem.eql(u8, key, "fingerprint")) {
            const fp_bytes = try r.readBytes();
            if (fp_bytes.len != 32) return Error.MalformedAssertion;
            var arr: [32]u8 = undefined;
            @memcpy(&arr, fp_bytes);
            parsed_fingerprint = arr;
        } else {
            // Unknown subject key — skip the value
            try r.skipItem();
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
        const m_len = try r.readMapHeader();
        if (m_len != 1) return Error.MalformedAssertion;

        // key = tag201(pred_cbor)
        // Record pred_cbor start/end for unknown assertion preservation
        try r.expectTag(cbor.Tag.leaf);
        const pred_start = r.pos;
        const pred_text = try r.readText();
        const pred_end = r.pos;

        // value = tag201(obj_cbor)
        try r.expectTag(cbor.Tag.leaf);
        const obj_start = r.pos;

        if (std.mem.eql(u8, pred_text, "ed25519-public")) {
            const b = try r.readBytes();
            if (b.len != 32) return Error.MalformedAssertion;
            var arr: [32]u8 = undefined;
            @memcpy(&arr, b);
            ed25519_public = arr;
        } else if (std.mem.eql(u8, pred_text, "ed25519-secret")) {
            const b = try r.readBytes();
            if (b.len != 32) return Error.MalformedAssertion;
            var arr: [32]u8 = undefined;
            @memcpy(&arr, b);
            ed25519_secret = arr;
        } else if (std.mem.eql(u8, pred_text, "ml-dsa-public")) {
            const b = try r.readBytes();
            const owned = try allocator.dupe(u8, b);
            alloc_ml_dsa_public = owned;
            ml_dsa_public = owned;
        } else if (std.mem.eql(u8, pred_text, "ml-dsa-secret")) {
            const b = try r.readBytes();
            const owned = try allocator.dupe(u8, b);
            alloc_ml_dsa_secret = owned;
            ml_dsa_secret = owned;
        } else if (std.mem.eql(u8, pred_text, "name")) {
            const t = try r.readText();
            const owned = try allocator.dupe(u8, t);
            alloc_name = owned;
            name = owned;
        } else if (std.mem.eql(u8, pred_text, "created")) {
            // Must be tag(1)(uint)
            const tag_val = try r.readTag();
            if (tag_val != cbor.Tag.epoch_time) return Error.InvalidCreated;
            const ts = try r.readUint();
            created = ts;
        } else if (std.mem.eql(u8, pred_text, "pre-backend")) {
            const t = try r.readText();
            const owned = try allocator.dupe(u8, t);
            alloc_pre_backend = owned;
            pre_backend = owned;
        } else if (std.mem.eql(u8, pred_text, "pre-public")) {
            const b = try r.readBytes();
            const owned = try allocator.dupe(u8, b);
            alloc_pre_public = owned;
            pre_public = owned;
        } else if (std.mem.eql(u8, pred_text, "pre-secret")) {
            const b = try r.readBytes();
            const owned = try allocator.dupe(u8, b);
            alloc_pre_secret = owned;
            pre_secret = owned;
        } else {
            // Unknown assertion: preserve raw CBOR bytes of pred and obj
            const pred_raw = try allocator.dupe(u8, bytes[pred_start..pred_end]);
            // Skip the object and capture its extent
            try r.skipItem();
            const obj_end = r.pos;
            const obj_raw = try allocator.dupe(u8, bytes[obj_start..obj_end]);
            try unknown_list.append(allocator, .{ .predicate_cbor = pred_raw, .object_cbor = obj_raw });
            // Object already skipped — continue to next assertion
            continue;
        }

        const obj_end = r.pos;
        _ = obj_end; // used only for unknown
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
    var pw1 = cbor.Writer.init(allocator);
    defer pw1.deinit();
    try pw1.writeText("zzz-unknown-first");
    const pred1 = try pw1.toOwned();
    defer allocator.free(pred1);

    var ow1 = cbor.Writer.init(allocator);
    defer ow1.deinit();
    try ow1.writeBytes(&[_]u8{ 0xDE, 0xAD });
    const obj1 = try ow1.toOwned();
    defer allocator.free(obj1);

    var pw2 = cbor.Writer.init(allocator);
    defer pw2.deinit();
    try pw2.writeText("aaa-unknown-second");
    const pred2 = try pw2.toOwned();
    defer allocator.free(pred2);

    var ow2 = cbor.Writer.init(allocator);
    defer ow2.deinit();
    try ow2.writeBytes(&[_]u8{ 0xBE, 0xEF });
    const obj2 = try ow2.toOwned();
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

    var subj_w = cbor.Writer.init(allocator);
    defer subj_w.deinit();
    try subj_w.writeMapHeader(3);
    try subj_w.writeText("type");
    try subj_w.writeText(TYPE);
    try subj_w.writeText("fingerprint");
    try subj_w.writeBytes(&wrong_fp);
    try subj_w.writeText("format-version");
    try subj_w.writeUint(FORMAT_VERSION);
    const subj_cbor = try subj_w.toOwned();
    defer allocator.free(subj_cbor);

    // Build assertion for ed25519-public
    var pred_w = cbor.Writer.init(allocator);
    defer pred_w.deinit();
    try pred_w.writeText("ed25519-public");
    const pred_cbor = try pred_w.toOwned();
    defer allocator.free(pred_cbor);

    var obj_w = cbor.Writer.init(allocator);
    defer obj_w.deinit();
    try obj_w.writeBytes(&pk);
    const obj_cbor = try obj_w.toOwned();
    defer allocator.free(obj_cbor);

    var env_w = cbor.Writer.init(allocator);
    defer env_w.deinit();
    try env_w.writeTag(cbor.Tag.envelope);
    try env_w.writeArrayHeader(2);
    try env_w.writeTag(cbor.Tag.leaf);
    try env_w.appendSlice(subj_cbor);
    try env_w.writeMapHeader(1);
    try env_w.writeTag(cbor.Tag.leaf);
    try env_w.appendSlice(pred_cbor);
    try env_w.writeTag(cbor.Tag.leaf);
    try env_w.appendSlice(obj_cbor);
    const env_bytes = try env_w.toOwned();
    defer allocator.free(env_bytes);

    try std.testing.expectError(Error.FingerprintMismatch, decode(allocator, env_bytes));
}

test "decode rejects missing ed25519-public" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x20} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);

    // Build valid subject map but NO ed25519-public assertion
    var subj_w = cbor.Writer.init(allocator);
    defer subj_w.deinit();
    try subj_w.writeMapHeader(3);
    try subj_w.writeText("type");
    try subj_w.writeText(TYPE);
    try subj_w.writeText("fingerprint");
    try subj_w.writeBytes(&fp.bytes);
    try subj_w.writeText("format-version");
    try subj_w.writeUint(FORMAT_VERSION);
    const subj_cbor = try subj_w.toOwned();
    defer allocator.free(subj_cbor);

    // Envelope with only subject (array of 1)
    var env_w = cbor.Writer.init(allocator);
    defer env_w.deinit();
    try env_w.writeTag(cbor.Tag.envelope);
    try env_w.writeArrayHeader(1);
    try env_w.writeTag(cbor.Tag.leaf);
    try env_w.appendSlice(subj_cbor);
    const env_bytes = try env_w.toOwned();
    defer allocator.free(env_bytes);

    try std.testing.expectError(Error.MissingEd25519Public, decode(allocator, env_bytes));
}

test "decode rejects wrong type string" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x30} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);

    var subj_w = cbor.Writer.init(allocator);
    defer subj_w.deinit();
    try subj_w.writeMapHeader(3);
    try subj_w.writeText("type");
    try subj_w.writeText("wrong.type");
    try subj_w.writeText("fingerprint");
    try subj_w.writeBytes(&fp.bytes);
    try subj_w.writeText("format-version");
    try subj_w.writeUint(FORMAT_VERSION);
    const subj_cbor = try subj_w.toOwned();
    defer allocator.free(subj_cbor);

    var env_w = cbor.Writer.init(allocator);
    defer env_w.deinit();
    try env_w.writeTag(cbor.Tag.envelope);
    try env_w.writeArrayHeader(1);
    try env_w.writeTag(cbor.Tag.leaf);
    try env_w.appendSlice(subj_cbor);
    const env_bytes = try env_w.toOwned();
    defer allocator.free(env_bytes);

    try std.testing.expectError(Error.WrongEnvelopeType, decode(allocator, env_bytes));
}

test "decode rejects wrong format-version" {
    const allocator = std.testing.allocator;

    const pk: [32]u8 = [_]u8{0x40} ** 32;
    const fp = fingerprint_mod.Fingerprint.fromEd25519(pk);

    var subj_w = cbor.Writer.init(allocator);
    defer subj_w.deinit();
    try subj_w.writeMapHeader(3);
    try subj_w.writeText("type");
    try subj_w.writeText(TYPE);
    try subj_w.writeText("fingerprint");
    try subj_w.writeBytes(&fp.bytes);
    try subj_w.writeText("format-version");
    try subj_w.writeUint(99);
    const subj_cbor = try subj_w.toOwned();
    defer allocator.free(subj_cbor);

    var env_w = cbor.Writer.init(allocator);
    defer env_w.deinit();
    try env_w.writeTag(cbor.Tag.envelope);
    try env_w.writeArrayHeader(1);
    try env_w.writeTag(cbor.Tag.leaf);
    try env_w.appendSlice(subj_cbor);
    const env_bytes = try env_w.toOwned();
    defer allocator.free(env_bytes);

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
    var r = cbor.Reader.init(ua.predicate_cbor);
    const pred_text = try r.readText();
    try std.testing.expectEqualStrings("dreamball-lineage", pred_text);

    // Re-encode and verify byte-identical
    const reemitted = try encode(allocator, decoded);
    defer allocator.free(reemitted);
    try std.testing.expectEqualSlices(u8, fixture, reemitted);
}
