//! Gordian-Envelope–style CBOR framing for DreamBall types.
//!
//! Envelope shape (simplified from bc-envelope):
//!     tag 200( [ leaf_subject, [pred0, obj0], [pred1, obj1], ... ] )
//!
//! Each inner 2-array is an assertion. The outer array has 1 + N elements
//! where N is the assertion count (0 when subject-only).
//!
//! Predicates are sorted per dCBOR canonical ordering (shorter canonical
//! encoding first, then lex over encoded-key bytes) so byte output is
//! deterministic.
//!
//! Vocabulary note — this file is the Gordian-Envelope CBOR encoder,
//! so the terms *envelope*, *subject*, *assertion*, *predicate*, and
//! *object* here refer to Blockchain Commons' native CBOR-format
//! vocabulary. They are intentionally preserved at this layer. The
//! higher-level Dreamball data model uses *node*, *core*, *attribute*,
//! *label*, and *value* (see
//! `docs/decisions/2026-04-20-terminology-rename.md`), which is what
//! every consumer of this file should use. Renamed user-facing
//! identifiers: `MalformedAssertion` → `MalformedAttribute`.
//!
//! Implementation: CBOR encode/decode is via the `zbor` library. The
//! dCBOR-canonical map ordering (shorter-first, then lex over encoded
//! bytes) lives in `src/dcbor.zig` and is orthogonal to zbor.

const std = @import("std");
const Allocator = std.mem.Allocator;

const zbor = @import("zbor");
const dcbor = @import("dcbor.zig");
const protocol = @import("protocol.zig");
const Fingerprint = @import("fingerprint.zig").Fingerprint;

pub const DREAMBALL_TYPE: []const u8 = "jelly.dreamball";
pub const LOOK_TYPE: []const u8 = "jelly.look";
pub const FEEL_TYPE: []const u8 = "jelly.feel";
pub const ACT_TYPE: []const u8 = "jelly.act";
pub const ASSET_TYPE: []const u8 = "jelly.asset";
pub const SKILL_TYPE: []const u8 = "jelly.skill";

const PairList = dcbor.PairList;

/// Write a canonical dCBOR map from a sorted PairList into `writer`.
fn emitMap(writer: *std.Io.Writer, pairs: PairList) !void {
    try zbor.builder.writeMap(writer, pairs.pairs.items.len);
    for (pairs.pairs.items) |p| {
        try zbor.builder.writeTextString(writer, p.key);
        try writer.writeAll(p.value);
    }
}

/// Write a subject-only envelope: tag 200( tag 201({subject_map}) ).
fn emitSubjectOnlyEnvelope(allocator: Allocator, subject_pairs: PairList) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try emitMap(w, subject_pairs);
    return ai.toOwnedSlice();
}

/// Write an envelope with assertions:
///   tag 200( [ tag 201({subject_map}), [pred0, obj0], [pred1, obj1], ... ] )
fn emitEnvelope(allocator: Allocator, subject_pairs: PairList, assertion_pairs: PairList) ![]u8 {
    if (assertion_pairs.pairs.items.len == 0) {
        return emitSubjectOnlyEnvelope(allocator, subject_pairs);
    }

    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeArray(w, 1 + assertion_pairs.pairs.items.len);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try emitMap(w, subject_pairs);

    for (assertion_pairs.pairs.items) |p| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, p.key);
        try w.writeAll(p.value);
    }
    return ai.toOwnedSlice();
}

// ============================================================================
// Public encoders per domain type.
// ============================================================================

pub fn encodeAsset(allocator: Allocator, a: protocol.Asset) ![]u8 {
    var subj = PairList.init(allocator);
    defer subj.deinit();
    try subj.addText("type", ASSET_TYPE);
    try subj.addUint("format-version", protocol.FORMAT_VERSION);
    try subj.addText("media-type", a.media_type);
    try subj.addBytes("hash", &a.hash);
    subj.sort();

    var asserts = PairList.init(allocator);
    defer asserts.deinit();
    if (a.embedded) |e| try asserts.addBytes("embedded", e);
    for (a.urls) |u| try asserts.addText("url", u);
    if (a.size) |s| try asserts.addUint("size", s);
    if (a.note) |n| try asserts.addText("note", n);
    asserts.sort();

    return emitEnvelope(allocator, subj, asserts);
}

pub fn encodeSkill(allocator: Allocator, s: protocol.Skill) ![]u8 {
    var subj = PairList.init(allocator);
    defer subj.deinit();
    try subj.addText("type", SKILL_TYPE);
    try subj.addUint("format-version", protocol.FORMAT_VERSION);
    try subj.addText("name", s.name);
    subj.sort();

    var asserts = PairList.init(allocator);
    defer asserts.deinit();
    if (s.trigger) |t| try asserts.addText("trigger", t);
    if (s.body) |b| try asserts.addText("body", b);
    if (s.asset) |a| {
        const asset_bytes = try encodeAsset(allocator, a);
        try asserts.addRawOwned("asset", asset_bytes);
    }
    for (s.requires) |r| try asserts.addText("requires", r);
    if (s.note) |n| try asserts.addText("note", n);
    asserts.sort();

    return emitEnvelope(allocator, subj, asserts);
}

pub fn encodeLook(allocator: Allocator, l: protocol.Look) ![]u8 {
    var subj = PairList.init(allocator);
    defer subj.deinit();
    try subj.addText("type", LOOK_TYPE);
    try subj.addUint("format-version", protocol.FORMAT_VERSION);
    subj.sort();

    var asserts = PairList.init(allocator);
    defer asserts.deinit();
    for (l.assets) |a| {
        const asset_bytes = try encodeAsset(allocator, a);
        try asserts.addRawOwned("asset", asset_bytes);
    }
    if (l.preview) |p| {
        const preview_bytes = try encodeAsset(allocator, p);
        try asserts.addRawOwned("preview", preview_bytes);
    }
    if (l.background) |bg| try asserts.addText("background", bg);
    if (l.note) |n| try asserts.addText("note", n);
    asserts.sort();

    return emitEnvelope(allocator, subj, asserts);
}

pub fn encodeFeel(allocator: Allocator, f: protocol.Feel) ![]u8 {
    var subj = PairList.init(allocator);
    defer subj.deinit();
    try subj.addText("type", FEEL_TYPE);
    try subj.addUint("format-version", protocol.FORMAT_VERSION);
    subj.sort();

    var asserts = PairList.init(allocator);
    defer asserts.deinit();
    if (f.personality) |p| try asserts.addText("personality", p);
    if (f.voice) |v| try asserts.addText("voice", v);
    for (f.values) |v| try asserts.addText("value", v);
    if (f.tempo) |t| try asserts.addText("tempo", t);
    if (f.note) |n| try asserts.addText("note", n);
    asserts.sort();

    return emitEnvelope(allocator, subj, asserts);
}

pub fn encodeAct(allocator: Allocator, a: protocol.Act) ![]u8 {
    var subj = PairList.init(allocator);
    defer subj.deinit();
    try subj.addText("type", ACT_TYPE);
    try subj.addUint("format-version", protocol.FORMAT_VERSION);
    subj.sort();

    var asserts = PairList.init(allocator);
    defer asserts.deinit();
    if (a.model) |m| try asserts.addText("model", m);
    if (a.system_prompt) |sp| try asserts.addText("system-prompt", sp);
    for (a.skills) |sk| {
        const skill_bytes = try encodeSkill(allocator, sk);
        try asserts.addRawOwned("skill", skill_bytes);
    }
    for (a.scripts) |sc| {
        const script_bytes = try encodeAsset(allocator, sc);
        try asserts.addRawOwned("script", script_bytes);
    }
    for (a.tools) |t| try asserts.addText("tool", t);
    if (a.note) |n| try asserts.addText("note", n);
    asserts.sort();

    return emitEnvelope(allocator, subj, asserts);
}

pub fn encodeDreamBall(allocator: Allocator, db: protocol.DreamBall) ![]u8 {
    var subj = PairList.init(allocator);
    defer subj.deinit();
    const type_str: []const u8 = if (db.dreamball_type) |t| t.toWireString() else DREAMBALL_TYPE;
    // Version bumps cascade: identity_pq → v3, else typed-or-guilded → v2, else v1.
    const fv: u32 = if (db.identity_pq != null)
        protocol.FORMAT_VERSION_V3
    else if (db.dreamball_type != null or db.guilds.len > 0)
        protocol.FORMAT_VERSION_V2
    else
        protocol.FORMAT_VERSION;
    try subj.addText("type", type_str);
    try subj.addUint("format-version", fv);
    try subj.addText("stage", db.stage.toString());
    try subj.addBytes("identity", &db.identity);
    if (db.identity_pq) |pq| try subj.addBytes("identity-pq", &pq);
    try subj.addBytes("genesis-hash", &db.genesis_hash);
    try subj.addUint("revision", db.revision);
    subj.sort();

    var asserts = PairList.init(allocator);
    defer asserts.deinit();
    if (db.name) |n| try asserts.addText("name", n);
    if (db.created) |t| try asserts.addEpoch("created", t);
    if (db.updated) |t| try asserts.addEpoch("updated", t);
    if (db.note) |n| try asserts.addText("note", n);

    if (db.look) |l| {
        const bytes = try encodeLook(allocator, l);
        try asserts.addRawOwned("look", bytes);
    }
    if (db.feel) |f| {
        const bytes = try encodeFeel(allocator, f);
        try asserts.addRawOwned("feel", bytes);
    }
    if (db.act) |a| {
        const bytes = try encodeAct(allocator, a);
        try asserts.addRawOwned("act", bytes);
    }

    if (db.field_kind) |fk| try asserts.addText("field-kind", fk);
    for (db.guilds) |fp| try asserts.addBytes("guild", &fp.bytes);
    for (db.contains) |fp| try asserts.addBytes("contains", &fp.bytes);
    for (db.derived_from) |fp| try asserts.addBytes("derived-from", &fp.bytes);

    // Signatures emitted last; predicate "signed" repeated per algorithm.
    for (db.signatures) |sig| {
        // Object: 2-text-array [alg, value_bytes]. Encode inline into bytes.
        var ai = std.Io.Writer.Allocating.init(allocator);
        errdefer ai.deinit();
        try zbor.builder.writeArray(&ai.writer, 2);
        try zbor.builder.writeTextString(&ai.writer, sig.alg);
        try zbor.builder.writeByteString(&ai.writer, sig.value);
        const obj_bytes = try ai.toOwnedSlice();
        try asserts.addRawOwned("signed", obj_bytes);
    }

    asserts.sort();

    return emitEnvelope(allocator, subj, asserts);
}

// ============================================================================
// Reader helpers — shared with identity_envelope.zig via dcbor.zig.
// These decoders walk a linear stream (tag → array header → map, etc.) and
// inherit dCBOR canonical-form enforcement (smallest-form integers,
// indefinite-length rejection) from `dcbor.readHead`.
// ============================================================================

const peekMajor = dcbor.peekMajor;
const readTagHead = dcbor.readTag;
const expectTag = dcbor.expectTag;
const readArrayHeader = dcbor.readArrayHeader;
const readMapHeader = dcbor.readMapHeader;
const readText = dcbor.readText;
const readBytes = dcbor.readBytes;
const readUint = dcbor.readUint;

// ============================================================================
// Decoder (subject only — sufficient for verify/show v0)
// ============================================================================

/// Decode subject-only round-trip companion for `encodeDreamBall`. Reads the
/// subject map whether or not assertions follow.
pub fn decodeDreamBallSubject(bytes: []const u8) !protocol.DreamBall {
    try dcbor.verifyCanonical(bytes);

    var cursor: usize = 0;
    try expectTag(bytes, &cursor, dcbor.Tag.envelope);

    // Peek — if major 4 we have an array of [subject, assertions...];
    // otherwise a subject-only envelope with tag 201 next.
    const next_major = try peekMajor(bytes, cursor);
    if (next_major == 4) {
        _ = try readArrayHeader(bytes, &cursor);
        try expectTag(bytes, &cursor, dcbor.Tag.leaf);
    } else {
        try expectTag(bytes, &cursor, dcbor.Tag.leaf);
    }

    const map_len = try readMapHeader(bytes, &cursor);

    var out = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
    };

    var i: u64 = 0;
    while (i < map_len) : (i += 1) {
        const key = try readText(bytes, &cursor);
        if (std.mem.eql(u8, key, "type")) {
            const t = try readText(bytes, &cursor);
            if (std.mem.eql(u8, t, DREAMBALL_TYPE)) {
                // untyped — pass
            } else if (protocol.DreamBallType.fromWireString(t)) |dt| {
                out.dreamball_type = dt;
            } else {
                return error.WrongType;
            }
        } else if (std.mem.eql(u8, key, "format-version")) {
            const v = try readUint(bytes, &cursor);
            if (v != protocol.FORMAT_VERSION and
                v != protocol.FORMAT_VERSION_V2 and
                v != protocol.FORMAT_VERSION_V3) return error.UnsupportedVersion;
        } else if (std.mem.eql(u8, key, "stage")) {
            const s = try readText(bytes, &cursor);
            out.stage = protocol.Stage.fromString(s) orelse return error.BadStage;
        } else if (std.mem.eql(u8, key, "identity")) {
            const b = try readBytes(bytes, &cursor);
            if (b.len != 32) return error.BadIdentity;
            @memcpy(&out.identity, b);
        } else if (std.mem.eql(u8, key, "identity-pq")) {
            const b = try readBytes(bytes, &cursor);
            if (b.len != protocol.ML_DSA_87_PUBLIC_KEY_LEN) return error.BadIdentityPq;
            var pq: [protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8 = undefined;
            @memcpy(&pq, b);
            out.identity_pq = pq;
        } else if (std.mem.eql(u8, key, "genesis-hash")) {
            const b = try readBytes(bytes, &cursor);
            if (b.len != 32) return error.BadGenesis;
            @memcpy(&out.genesis_hash, b);
        } else if (std.mem.eql(u8, key, "revision")) {
            const v = try readUint(bytes, &cursor);
            out.revision = @intCast(v);
        } else {
            return error.UnknownSubjectField;
        }
    }
    return out;
}

// ============================================================================
// Byte-level signature strip — the v0 path to signature verification.
//
// The signer calls `encodeDreamBall` twice: once with `signatures = &.{}` to
// get the canonical unsigned bytes, then once with signatures attached to
// get the final on-disk envelope. To verify, we need to reconstruct those
// unsigned bytes from an on-disk envelope — that is, remove every `signed`
// assertion and rewrite the outer array count.
//
// We do this at the byte level rather than by round-tripping through the
// in-memory DreamBall struct, because that would require fully parsing the
// nested look/feel/act envelopes back into the struct (which is substantial
// work and doesn't change the verification outcome).
// ============================================================================

pub const CapturedSignature = struct {
    /// Slice into the source bytes — copy before dropping the source.
    alg: []const u8,
    /// Slice into the source bytes — copy before dropping the source.
    value: []const u8,
};

pub const StripResult = struct {
    /// Newly-allocated envelope bytes with every `signed` assertion removed.
    /// Caller owns.
    unsigned: []u8,
    /// Signatures captured from the stripped assertions, in the order they
    /// appeared. Each `alg` and `value` is a slice into the *source* envelope
    /// — callers must either dupe the bytes or keep the source alive.
    signatures: []CapturedSignature,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *StripResult) void {
        self.allocator.free(self.unsigned);
        self.allocator.free(self.signatures);
        self.* = undefined;
    }
};

pub const StripError = error{
    Truncated,
    UnsupportedType,
    NotEnvelope,
    MalformedAttribute,
    OutOfMemory,
    // zbor.builder.* emit `error.WriteFailed` through `std.Io.Writer`.
    WriteFailed,
};

pub fn stripSignatures(allocator: std.mem.Allocator, bytes: []const u8) StripError!StripResult {
    var cursor: usize = 0;
    expectTag(bytes, &cursor, dcbor.Tag.envelope) catch return StripError.NotEnvelope;
    const body_start = cursor;

    // If the next item is not an array, this is a subject-only envelope —
    // nothing to strip. Return a copy.
    const next_major = peekMajor(bytes, cursor) catch return StripError.Truncated;
    if (next_major != 4) {
        const copy = try allocator.dupe(u8, bytes);
        return .{
            .unsigned = copy,
            .signatures = try allocator.alloc(CapturedSignature, 0),
            .allocator = allocator,
        };
    }

    const element_count = readArrayHeader(bytes, &cursor) catch return StripError.Truncated;
    if (element_count == 0) return StripError.MalformedAttribute;

    // First element is the tag-201 subject leaf. Compute its span.
    const subject_start = cursor;
    const subject_len = dcbor.itemLen(bytes, subject_start) catch return StripError.Truncated;
    cursor = subject_start + subject_len;

    var kept_ranges: std.ArrayList([2]usize) = .empty; // [start, end)
    defer kept_ranges.deinit(allocator);
    var captured: std.ArrayList(CapturedSignature) = .empty;
    errdefer captured.deinit(allocator);

    try kept_ranges.append(allocator, .{ subject_start, subject_start + subject_len });

    var i: u64 = 1;
    while (i < element_count) : (i += 1) {
        const elem_start = cursor;
        const elem_len = dcbor.itemLen(bytes, elem_start) catch return StripError.Truncated;
        const elem_end = elem_start + elem_len;

        // Expect the element to be a 2-array [predicate_text, object].
        var inner_cursor: usize = elem_start;
        const h = readArrayHeader(bytes, &inner_cursor) catch return StripError.MalformedAttribute;
        if (h != 2) return StripError.MalformedAttribute;

        const pred = readText(bytes, &inner_cursor) catch return StripError.MalformedAttribute;

        if (std.mem.eql(u8, pred, "signed")) {
            // Object shape: [alg_text, value_bytes]. Parse to capture.
            const obj_arr_len = readArrayHeader(bytes, &inner_cursor) catch return StripError.MalformedAttribute;
            if (obj_arr_len != 2) return StripError.MalformedAttribute;
            const alg = readText(bytes, &inner_cursor) catch return StripError.MalformedAttribute;
            const val = readBytes(bytes, &inner_cursor) catch return StripError.MalformedAttribute;
            try captured.append(allocator, .{ .alg = alg, .value = val });
            // Do NOT add to kept_ranges — this assertion is stripped.
        } else {
            try kept_ranges.append(allocator, .{ elem_start, elem_end });
        }

        cursor = elem_end;
    }

    // Rebuild the envelope.
    const new_count = kept_ranges.items.len;
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    if (new_count == 1) {
        // Only the subject — emit as subject-only (no array wrapper) so the
        // canonical form matches what the encoder would have produced for a
        // DreamBall with signatures=[] and no other assertions.
        const r_subj = kept_ranges.items[0];
        try w.writeAll(bytes[r_subj[0]..r_subj[1]]);
    } else {
        try zbor.builder.writeArray(w, new_count);
        for (kept_ranges.items) |rr| {
            try w.writeAll(bytes[rr[0]..rr[1]]);
        }
    }
    // silence unused warning on body_start
    _ = body_start;

    const unsigned = try ai.toOwnedSlice();
    const sigs = try captured.toOwnedSlice(allocator);
    return .{ .unsigned = unsigned, .signatures = sigs, .allocator = allocator };
}

// ============================================================================
// Full envelope decoder — reads subject + all assertions into a DreamBall
// struct. Contrast with `decodeDreamBallSubject` above which only reads the
// load-bearing subject fields (the lightweight hot path).
//
// Memory model: all owned allocations are made through the `arena`
// argument. Callers are expected to pass an arena allocator and free
// everything in one `arena.deinit()` after consuming the result.
//
// Scope note: v2 MVP fully decodes the top-level DreamBall, Look, Feel,
// Act, Asset, and Skill envelopes. Memory / knowledge-graph /
// emotional-register / interaction-set / guild-policy assertions are
// captured as raw CBOR-envelope byte slices inside the parent's
// `raw_assertions` field (not yet surfaced on the typed struct) —
// consumers who need them today can walk the bytes themselves. Full
// decode for those lands next.
// ============================================================================

/// Walk a subject's CBOR map, decoding known keys into a DreamBall's
/// subject fields. Sets `out.dreamball_type` on typed subjects.
fn readSubjectMap(bytes: []const u8, cursor: *usize, out: *protocol.DreamBall) !void {
    const map_len = try readMapHeader(bytes, cursor);
    var i: u64 = 0;
    while (i < map_len) : (i += 1) {
        const key = try readText(bytes, cursor);
        if (std.mem.eql(u8, key, "type")) {
            const t = try readText(bytes, cursor);
            if (!std.mem.eql(u8, t, DREAMBALL_TYPE)) {
                out.dreamball_type = protocol.DreamBallType.fromWireString(t) orelse return error.UnknownType;
            }
        } else if (std.mem.eql(u8, key, "format-version")) {
            const v = try readUint(bytes, cursor);
            if (v != protocol.FORMAT_VERSION and
                v != protocol.FORMAT_VERSION_V2 and
                v != protocol.FORMAT_VERSION_V3) return error.UnsupportedVersion;
        } else if (std.mem.eql(u8, key, "stage")) {
            const s = try readText(bytes, cursor);
            out.stage = protocol.Stage.fromString(s) orelse return error.BadStage;
        } else if (std.mem.eql(u8, key, "identity")) {
            const b = try readBytes(bytes, cursor);
            if (b.len != 32) return error.BadIdentity;
            @memcpy(&out.identity, b);
        } else if (std.mem.eql(u8, key, "identity-pq")) {
            const b = try readBytes(bytes, cursor);
            if (b.len != protocol.ML_DSA_87_PUBLIC_KEY_LEN) return error.BadIdentityPq;
            var pq: [protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8 = undefined;
            @memcpy(&pq, b);
            out.identity_pq = pq;
        } else if (std.mem.eql(u8, key, "genesis-hash")) {
            const b = try readBytes(bytes, cursor);
            if (b.len != 32) return error.BadGenesis;
            @memcpy(&out.genesis_hash, b);
        } else if (std.mem.eql(u8, key, "revision")) {
            out.revision = @intCast(try readUint(bytes, cursor));
        } else {
            // Unknown subject keys are rejected — they are load-bearing.
            return error.UnknownSubjectField;
        }
    }
}

/// Consume the envelope/array/leaf prefix of an inner envelope (Asset, Skill,
/// Look, Feel, Act, or the top-level DreamBall). On return, `cursor` points
/// at the subject map header and the number of *following* assertion
/// elements is returned. For subject-only envelopes the count is 0.
fn enterEnvelope(bytes: []const u8, cursor: *usize) !u64 {
    try expectTag(bytes, cursor, dcbor.Tag.envelope);
    const next_major = try peekMajor(bytes, cursor.*);
    var assertion_count: u64 = 0;
    if (next_major == 4) {
        const total = try readArrayHeader(bytes, cursor);
        assertion_count = total - 1;
    }
    try expectTag(bytes, cursor, dcbor.Tag.leaf);
    return assertion_count;
}

fn decodeAssetFromEnvelope(arena: Allocator, env_bytes: []const u8) !protocol.Asset {
    var cursor: usize = 0;
    const assertion_count = try enterEnvelope(env_bytes, &cursor);

    var media_type: []const u8 = "";
    var hash: [32]u8 = [_]u8{0} ** 32;
    const subj_len = try readMapHeader(env_bytes, &cursor);
    var i: u64 = 0;
    while (i < subj_len) : (i += 1) {
        const key = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, key, "type")) {
            _ = try readText(env_bytes, &cursor);
        } else if (std.mem.eql(u8, key, "format-version")) {
            _ = try readUint(env_bytes, &cursor);
        } else if (std.mem.eql(u8, key, "media-type")) {
            const v = try readText(env_bytes, &cursor);
            media_type = try arena.dupe(u8, v);
        } else if (std.mem.eql(u8, key, "hash")) {
            const v = try readBytes(env_bytes, &cursor);
            if (v.len != 32) return error.BadHash;
            @memcpy(&hash, v);
        } else return error.UnknownAssetField;
    }

    var urls: std.ArrayList([]const u8) = .empty;
    var embedded: ?[]const u8 = null;
    var size: ?u64 = null;
    var note: ?[]const u8 = null;

    var a_i: u64 = 0;
    while (a_i < assertion_count) : (a_i += 1) {
        const h = try readArrayHeader(env_bytes, &cursor);
        if (h != 2) return error.BadAssertion;
        const pred = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, pred, "url")) {
            const v = try readText(env_bytes, &cursor);
            try urls.append(arena, try arena.dupe(u8, v));
        } else if (std.mem.eql(u8, pred, "embedded")) {
            const v = try readBytes(env_bytes, &cursor);
            embedded = try arena.dupe(u8, v);
        } else if (std.mem.eql(u8, pred, "size")) {
            size = try readUint(env_bytes, &cursor);
        } else if (std.mem.eql(u8, pred, "note")) {
            const v = try readText(env_bytes, &cursor);
            note = try arena.dupe(u8, v);
        } else return error.UnknownAssetAssertion;
    }

    return .{
        .media_type = media_type,
        .hash = hash,
        .urls = try urls.toOwnedSlice(arena),
        .embedded = embedded,
        .size = size,
        .note = note,
    };
}

fn decodeSkillFromEnvelope(arena: Allocator, env_bytes: []const u8) !protocol.Skill {
    var cursor: usize = 0;
    const assertion_count = try enterEnvelope(env_bytes, &cursor);

    var name: []const u8 = "";
    const subj_len = try readMapHeader(env_bytes, &cursor);
    var i: u64 = 0;
    while (i < subj_len) : (i += 1) {
        const key = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, key, "type")) {
            _ = try readText(env_bytes, &cursor);
        } else if (std.mem.eql(u8, key, "format-version")) {
            _ = try readUint(env_bytes, &cursor);
        } else if (std.mem.eql(u8, key, "name")) {
            name = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else return error.UnknownSkillField;
    }

    var trigger: ?[]const u8 = null;
    var body: ?[]const u8 = null;
    var asset: ?protocol.Asset = null;
    var requires: std.ArrayList([]const u8) = .empty;
    var note: ?[]const u8 = null;

    var a_i: u64 = 0;
    while (a_i < assertion_count) : (a_i += 1) {
        const h = try readArrayHeader(env_bytes, &cursor);
        if (h != 2) return error.BadAssertion;
        const pred = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, pred, "trigger")) {
            trigger = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "body")) {
            body = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "asset")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            asset = try decodeAssetFromEnvelope(arena, sub);
        } else if (std.mem.eql(u8, pred, "requires")) {
            try requires.append(arena, try arena.dupe(u8, try readText(env_bytes, &cursor)));
        } else if (std.mem.eql(u8, pred, "note")) {
            note = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else return error.UnknownSkillAssertion;
    }

    return .{
        .name = name,
        .trigger = trigger,
        .body = body,
        .asset = asset,
        .requires = try requires.toOwnedSlice(arena),
        .note = note,
    };
}

fn decodeLookFromEnvelope(arena: Allocator, env_bytes: []const u8) !protocol.Look {
    var cursor: usize = 0;
    const assertion_count = try enterEnvelope(env_bytes, &cursor);

    const subj_len = try readMapHeader(env_bytes, &cursor);
    var i: u64 = 0;
    while (i < subj_len) : (i += 1) {
        const key = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, key, "type")) {
            _ = try readText(env_bytes, &cursor);
        } else if (std.mem.eql(u8, key, "format-version")) {
            _ = try readUint(env_bytes, &cursor);
        } else return error.UnknownLookField;
    }

    var assets: std.ArrayList(protocol.Asset) = .empty;
    var preview: ?protocol.Asset = null;
    var background: ?[]const u8 = null;
    var note: ?[]const u8 = null;

    var a_i: u64 = 0;
    while (a_i < assertion_count) : (a_i += 1) {
        const h = try readArrayHeader(env_bytes, &cursor);
        if (h != 2) return error.BadAssertion;
        const pred = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, pred, "asset")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            try assets.append(arena, try decodeAssetFromEnvelope(arena, sub));
        } else if (std.mem.eql(u8, pred, "preview")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            preview = try decodeAssetFromEnvelope(arena, sub);
        } else if (std.mem.eql(u8, pred, "background")) {
            background = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "note")) {
            note = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else return error.UnknownLookAssertion;
    }

    return .{
        .assets = try assets.toOwnedSlice(arena),
        .preview = preview,
        .background = background,
        .note = note,
    };
}

fn decodeFeelFromEnvelope(arena: Allocator, env_bytes: []const u8) !protocol.Feel {
    var cursor: usize = 0;
    const assertion_count = try enterEnvelope(env_bytes, &cursor);

    const subj_len = try readMapHeader(env_bytes, &cursor);
    var i: u64 = 0;
    while (i < subj_len) : (i += 1) {
        const key = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, key, "type")) {
            _ = try readText(env_bytes, &cursor);
        } else if (std.mem.eql(u8, key, "format-version")) {
            _ = try readUint(env_bytes, &cursor);
        } else return error.UnknownFeelField;
    }

    var personality: ?[]const u8 = null;
    var voice: ?[]const u8 = null;
    var values: std.ArrayList([]const u8) = .empty;
    var tempo: ?[]const u8 = null;
    var note: ?[]const u8 = null;

    var a_i: u64 = 0;
    while (a_i < assertion_count) : (a_i += 1) {
        const h = try readArrayHeader(env_bytes, &cursor);
        if (h != 2) return error.BadAssertion;
        const pred = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, pred, "personality")) {
            personality = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "voice")) {
            voice = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "value")) {
            try values.append(arena, try arena.dupe(u8, try readText(env_bytes, &cursor)));
        } else if (std.mem.eql(u8, pred, "tempo")) {
            tempo = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "note")) {
            note = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else return error.UnknownFeelAssertion;
    }

    return .{
        .personality = personality,
        .voice = voice,
        .values = try values.toOwnedSlice(arena),
        .tempo = tempo,
        .note = note,
    };
}

fn decodeActFromEnvelope(arena: Allocator, env_bytes: []const u8) !protocol.Act {
    var cursor: usize = 0;
    const assertion_count = try enterEnvelope(env_bytes, &cursor);

    const subj_len = try readMapHeader(env_bytes, &cursor);
    var i: u64 = 0;
    while (i < subj_len) : (i += 1) {
        const key = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, key, "type")) {
            _ = try readText(env_bytes, &cursor);
        } else if (std.mem.eql(u8, key, "format-version")) {
            _ = try readUint(env_bytes, &cursor);
        } else return error.UnknownActField;
    }

    var model: ?[]const u8 = null;
    var system_prompt: ?[]const u8 = null;
    var skills: std.ArrayList(protocol.Skill) = .empty;
    var scripts: std.ArrayList(protocol.Asset) = .empty;
    var tools: std.ArrayList([]const u8) = .empty;
    var note: ?[]const u8 = null;

    var a_i: u64 = 0;
    while (a_i < assertion_count) : (a_i += 1) {
        const h = try readArrayHeader(env_bytes, &cursor);
        if (h != 2) return error.BadAssertion;
        const pred = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, pred, "model")) {
            model = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "system-prompt")) {
            system_prompt = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "skill")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            try skills.append(arena, try decodeSkillFromEnvelope(arena, sub));
        } else if (std.mem.eql(u8, pred, "script")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            try scripts.append(arena, try decodeAssetFromEnvelope(arena, sub));
        } else if (std.mem.eql(u8, pred, "tool")) {
            try tools.append(arena, try arena.dupe(u8, try readText(env_bytes, &cursor)));
        } else if (std.mem.eql(u8, pred, "note")) {
            note = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else return error.UnknownActAssertion;
    }

    return .{
        .model = model,
        .system_prompt = system_prompt,
        .skills = try skills.toOwnedSlice(arena),
        .scripts = try scripts.toOwnedSlice(arena),
        .tools = try tools.toOwnedSlice(arena),
        .note = note,
    };
}

/// Full DreamBall decoder — subject + every assertion we know how to
/// interpret. Unknown assertions are rejected (fail-loud).
pub fn decodeDreamBall(arena: Allocator, env_bytes: []const u8) !protocol.DreamBall {
    try dcbor.verifyCanonical(env_bytes);

    var cursor: usize = 0;
    const assertion_count = try enterEnvelope(env_bytes, &cursor);

    var out = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
    };
    try readSubjectMap(env_bytes, &cursor, &out);

    var name: ?[]const u8 = null;
    var created: ?i64 = null;
    var updated: ?i64 = null;
    var note: ?[]const u8 = null;
    var contains: std.ArrayList(Fingerprint) = .empty;
    var derived_from: std.ArrayList(Fingerprint) = .empty;
    var guilds: std.ArrayList(Fingerprint) = .empty;
    var sigs: std.ArrayList(protocol.Signature) = .empty;

    var a_i: u64 = 0;
    while (a_i < assertion_count) : (a_i += 1) {
        const h = try readArrayHeader(env_bytes, &cursor);
        if (h != 2) return error.BadAssertion;
        const pred = try readText(env_bytes, &cursor);
        if (std.mem.eql(u8, pred, "name")) {
            name = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "note")) {
            note = try arena.dupe(u8, try readText(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "created")) {
            try expectTag(env_bytes, &cursor, dcbor.Tag.epoch_time);
            created = @intCast(try readUint(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "updated")) {
            try expectTag(env_bytes, &cursor, dcbor.Tag.epoch_time);
            updated = @intCast(try readUint(env_bytes, &cursor));
        } else if (std.mem.eql(u8, pred, "contains")) {
            const b = try readBytes(env_bytes, &cursor);
            if (b.len != 32) return error.BadFingerprint;
            var fp: Fingerprint = undefined;
            @memcpy(&fp.bytes, b);
            try contains.append(arena, fp);
        } else if (std.mem.eql(u8, pred, "derived-from")) {
            const b = try readBytes(env_bytes, &cursor);
            if (b.len != 32) return error.BadFingerprint;
            var fp: Fingerprint = undefined;
            @memcpy(&fp.bytes, b);
            try derived_from.append(arena, fp);
        } else if (std.mem.eql(u8, pred, "guild")) {
            const b = try readBytes(env_bytes, &cursor);
            if (b.len != 32) return error.BadFingerprint;
            var fp: Fingerprint = undefined;
            @memcpy(&fp.bytes, b);
            try guilds.append(arena, fp);
        } else if (std.mem.eql(u8, pred, "signed")) {
            const sh = try readArrayHeader(env_bytes, &cursor);
            if (sh != 2) return error.BadAssertion;
            const alg = try readText(env_bytes, &cursor);
            const val = try readBytes(env_bytes, &cursor);
            try sigs.append(arena, .{
                .alg = try arena.dupe(u8, alg),
                .value = try arena.dupe(u8, val),
            });
        } else if (std.mem.eql(u8, pred, "look")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            out.look = try decodeLookFromEnvelope(arena, sub);
        } else if (std.mem.eql(u8, pred, "feel")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            out.feel = try decodeFeelFromEnvelope(arena, sub);
        } else if (std.mem.eql(u8, pred, "act")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            out.act = try decodeActFromEnvelope(arena, sub);
        } else {
            // Skip unknown assertions by walking past the object — keeps us
            // forward-compatible with v2.x envelopes that add new slots.
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            cursor += len;
        }
    }

    out.name = name;
    out.created = created;
    out.updated = updated;
    out.note = note;
    out.contains = try contains.toOwnedSlice(arena);
    out.derived_from = try derived_from.toOwnedSlice(arena);
    out.guilds = try guilds.toOwnedSlice(arena);
    out.signatures = try sigs.toOwnedSlice(arena);

    return out;
}

// ============================================================================
// Tests
// ============================================================================

test "encodeDreamBall produces stable bytes (subject only)" {
    const allocator = std.testing.allocator;
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 3,
    };
    const a = try encodeDreamBall(allocator, db);
    defer allocator.free(a);
    const b = try encodeDreamBall(allocator, db);
    defer allocator.free(b);
    try std.testing.expectEqualSlices(u8, a, b);
    // Starts with tag 200 then tag 201 (subject only, no assertions).
    try std.testing.expect(a.len > 4);
    try std.testing.expectEqual(@as(u8, 0xD8), a[0]);
    try std.testing.expectEqual(@as(u8, 0xC8), a[1]);
    try std.testing.expectEqual(@as(u8, 0xD8), a[2]);
    try std.testing.expectEqual(@as(u8, 0xC9), a[3]);
}

test "encode → decode subject round-trip" {
    const allocator = std.testing.allocator;
    const db = protocol.DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{0xAA} ** 32,
        .genesis_hash = [_]u8{0xBB} ** 32,
        .revision = 17,
    };
    const bytes = try encodeDreamBall(allocator, db);
    defer allocator.free(bytes);
    const decoded = try decodeDreamBallSubject(bytes);
    try std.testing.expectEqual(db.stage, decoded.stage);
    try std.testing.expectEqual(db.revision, decoded.revision);
    try std.testing.expectEqualSlices(u8, &db.identity, &decoded.identity);
    try std.testing.expectEqualSlices(u8, &db.genesis_hash, &decoded.genesis_hash);
}

test "encodeLook emits envelope with nested asset" {
    const allocator = std.testing.allocator;
    const urls = [_][]const u8{"https://cdn.example/a.glb"};
    const assets = [_]protocol.Asset{
        .{ .media_type = "model/gltf-binary", .hash = [_]u8{0xAB} ** 32, .urls = &urls },
    };
    const look = protocol.Look{ .assets = &assets, .background = "color:#000" };
    const bytes = try encodeLook(allocator, look);
    defer allocator.free(bytes);
    // Tag 200 envelope, then array header (subject + assertions).
    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xC8), bytes[1]);
}

test "stripSignatures recovers the canonical unsigned bytes" {
    const allocator = std.testing.allocator;

    // Reference: encode the DreamBall with signatures=[] — this is what the
    // signer fed into Ed25519.sign().
    const db_unsigned = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{0x07} ** 32,
        .genesis_hash = [_]u8{0x09} ** 32,
        .revision = 0,
    };
    const expected_unsigned = try encodeDreamBall(allocator, db_unsigned);
    defer allocator.free(expected_unsigned);

    // Attach two fake signatures and re-encode.
    const ed_sig: [protocol.ED25519_SIGNATURE_LEN]u8 = [_]u8{0x11} ** protocol.ED25519_SIGNATURE_LEN;
    const mldsa_ph: [protocol.ML_DSA_87_SIGNATURE_LEN]u8 = [_]u8{0} ** protocol.ML_DSA_87_SIGNATURE_LEN;
    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = &mldsa_ph },
    };
    var db_signed = db_unsigned;
    db_signed.signatures = &sigs;
    const signed_bytes = try encodeDreamBall(allocator, db_signed);
    defer allocator.free(signed_bytes);

    // Strip and compare — must be byte-identical to the signer's input.
    var stripped = try stripSignatures(allocator, signed_bytes);
    defer stripped.deinit();
    try std.testing.expectEqualSlices(u8, expected_unsigned, stripped.unsigned);
    try std.testing.expectEqual(@as(usize, 2), stripped.signatures.len);
    try std.testing.expectEqualStrings("ed25519", stripped.signatures[0].alg);
    try std.testing.expectEqualStrings("ml-dsa-87", stripped.signatures[1].alg);
    try std.testing.expectEqualSlices(u8, &ed_sig, stripped.signatures[0].value);
}

test "decodeDreamBall full round-trip — populated envelope" {
    const gpa = std.testing.allocator;
    var arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();

    const urls = [_][]const u8{"https://cdn.example/a.glb"};
    const assets = [_]protocol.Asset{.{
        .media_type = "model/gltf-binary",
        .hash = [_]u8{0xAA} ** 32,
        .urls = &urls,
    }};
    const look = protocol.Look{ .assets = &assets, .background = "color:#123" };

    const values = [_][]const u8{ "curiosity", "clarity" };
    const feel = protocol.Feel{
        .personality = "playful",
        .voice = "quick",
        .values = &values,
    };

    const skills = [_]protocol.Skill{
        .{ .name = "haiku", .trigger = "when asked for a poem" },
    };
    const tools = [_][]const u8{"web.search"};
    const act = protocol.Act{
        .model = "claude-opus-4-7",
        .system_prompt = "You are curiosity.",
        .skills = &skills,
        .tools = &tools,
    };

    const contains = [_]Fingerprint{.{ .bytes = [_]u8{0xCC} ** 32 }};
    const guilds = [_]Fingerprint{.{ .bytes = [_]u8{0xDD} ** 32 }};
    const ed_sig = [_]u8{0x11} ** protocol.ED25519_SIGNATURE_LEN;

    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
    };

    const db = protocol.DreamBall{
        .stage = .dreamball,
        .dreamball_type = .agent,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 7,
        .name = "Aspect of Curiosity",
        .created = 1712534400,
        .updated = 1713000000,
        .note = "first fruition",
        .look = look,
        .feel = feel,
        .act = act,
        .contains = &contains,
        .guilds = &guilds,
        .signatures = &sigs,
    };

    const bytes = try encodeDreamBall(gpa, db);
    defer gpa.free(bytes);

    const decoded = try decodeDreamBall(arena, bytes);

    try std.testing.expectEqual(protocol.DreamBallType.agent, decoded.dreamball_type.?);
    try std.testing.expectEqual(db.stage, decoded.stage);
    try std.testing.expectEqual(db.revision, decoded.revision);
    try std.testing.expectEqualSlices(u8, &db.identity, &decoded.identity);
    try std.testing.expectEqualSlices(u8, "Aspect of Curiosity", decoded.name.?);
    try std.testing.expectEqual(@as(i64, 1712534400), decoded.created.?);
    try std.testing.expectEqual(@as(i64, 1713000000), decoded.updated.?);
    try std.testing.expect(decoded.look != null);
    try std.testing.expectEqualStrings("color:#123", decoded.look.?.background.?);
    try std.testing.expectEqual(@as(usize, 1), decoded.look.?.assets.len);
    try std.testing.expectEqualStrings("model/gltf-binary", decoded.look.?.assets[0].media_type);
    try std.testing.expect(decoded.feel != null);
    try std.testing.expectEqualStrings("playful", decoded.feel.?.personality.?);
    try std.testing.expectEqual(@as(usize, 2), decoded.feel.?.values.len);
    try std.testing.expect(decoded.act != null);
    try std.testing.expectEqualStrings("claude-opus-4-7", decoded.act.?.model.?);
    try std.testing.expectEqual(@as(usize, 1), decoded.act.?.skills.len);
    try std.testing.expectEqualStrings("haiku", decoded.act.?.skills[0].name);
    try std.testing.expectEqual(@as(usize, 1), decoded.act.?.tools.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.contains.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.guilds.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.signatures.len);
    try std.testing.expectEqualStrings("ed25519", decoded.signatures[0].alg);
}

test "populated round-trip — envelope with all slots + signatures" {
    const allocator = std.testing.allocator;

    const urls = [_][]const u8{"https://example/a.glb"};
    const la = [_]protocol.Asset{.{
        .media_type = "model/gltf-binary",
        .hash = [_]u8{0xAA} ** 32,
        .urls = &urls,
    }};
    const look = protocol.Look{ .assets = &la, .background = "color:#123" };

    const values = [_][]const u8{ "curiosity", "clarity" };
    const feel = protocol.Feel{
        .personality = "playful",
        .voice = "quick",
        .values = &values,
        .tempo = "fast",
    };

    const tools = [_][]const u8{"web.search"};
    const act = protocol.Act{
        .model = "claude-opus-4-7",
        .system_prompt = "You are an aspect of curiosity.",
        .tools = &tools,
    };

    const contains = [_]Fingerprint{.{ .bytes = [_]u8{0xCC} ** 32 }};
    const derived = [_]Fingerprint{.{ .bytes = [_]u8{0xDD} ** 32 }};

    const ed_sig: [protocol.ED25519_SIGNATURE_LEN]u8 = [_]u8{0x11} ** protocol.ED25519_SIGNATURE_LEN;
    const mldsa_ph: [protocol.ML_DSA_87_SIGNATURE_LEN]u8 = [_]u8{0} ** protocol.ML_DSA_87_SIGNATURE_LEN;
    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = &mldsa_ph },
    };

    const db = protocol.DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 7,
        .name = "Aspect of Curiosity",
        .created = 1712534400,
        .updated = 1713000000,
        .note = "first fruition",
        .look = look,
        .feel = feel,
        .act = act,
        .contains = &contains,
        .derived_from = &derived,
        .signatures = &sigs,
    };

    const bytes = try encodeDreamBall(allocator, db);
    defer allocator.free(bytes);

    // Sanity: first 2 bytes are tag 200.
    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xC8), bytes[1]);

    // Subject round-trip still works despite the full assertion list.
    const decoded = try decodeDreamBallSubject(bytes);
    try std.testing.expectEqual(db.stage, decoded.stage);
    try std.testing.expectEqual(db.revision, decoded.revision);
    try std.testing.expectEqualSlices(u8, &db.identity, &decoded.identity);

    // isFullySigned with placeholder policy accepts this envelope.
    try std.testing.expect(db.isFullySigned(.allow_mldsa_placeholder));
    try std.testing.expect(!db.isFullySigned(.strict));

    // Byte length is bigger than subject-only.
    const db_bare = protocol.DreamBall{
        .stage = .dreamball,
        .identity = db.identity,
        .genesis_hash = db.genesis_hash,
        .revision = db.revision,
    };
    const bare = try encodeDreamBall(allocator, db_bare);
    defer allocator.free(bare);
    try std.testing.expect(bytes.len > bare.len);
}
