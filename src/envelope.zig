//! Gordian-Envelope–style framing for DreamBall types.
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

const std = @import("std");
const Allocator = std.mem.Allocator;

const cbor = @import("cbor.zig");
const protocol = @import("protocol.zig");
const Fingerprint = @import("fingerprint.zig").Fingerprint;

pub const DREAMBALL_TYPE: []const u8 = "jelly.dreamball";
pub const LOOK_TYPE: []const u8 = "jelly.look";
pub const FEEL_TYPE: []const u8 = "jelly.feel";
pub const ACT_TYPE: []const u8 = "jelly.act";
pub const ASSET_TYPE: []const u8 = "jelly.asset";
pub const SKILL_TYPE: []const u8 = "jelly.skill";

/// One pre-serialized key/value pair. `key` is the text-encoded predicate;
/// `value` is already dCBOR bytes. Used by the subject-map and assertion-list
/// emitters for deterministic ordering.
const Pair = struct { key: []const u8, value: []const u8 };

fn pairLt(_: void, a: Pair, b: Pair) bool {
    if (a.key.len != b.key.len) return a.key.len < b.key.len;
    return std.mem.lessThan(u8, a.key, b.key);
}

const PairList = struct {
    pairs: std.ArrayList(Pair),
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

    fn addEpoch(self: *PairList, key: []const u8, epoch: i64) !void {
        var w = cbor.Writer.init(self.allocator);
        errdefer w.deinit();
        try w.writeTag(cbor.Tag.epoch_time);
        try w.writeUint(@intCast(epoch));
        const bytes = try w.toOwned();
        try self.addOwned(key, bytes);
    }

    /// Consumes `inner_bytes`: the PairList takes ownership.
    fn addRawOwned(self: *PairList, key: []const u8, inner_bytes: []u8) !void {
        try self.addOwned(key, inner_bytes);
    }

    fn sort(self: *PairList) void {
        std.sort.insertion(Pair, self.pairs.items, {}, pairLt);
    }
};

/// Write a canonical dCBOR map from a sorted PairList into `w`.
fn emitMap(w: *cbor.Writer, pairs: PairList) !void {
    try w.writeMapHeader(pairs.pairs.items.len);
    for (pairs.pairs.items) |p| {
        try w.writeText(p.key);
        try w.appendSlice(p.value);
    }
}

/// Write a subject-only envelope: tag 200( tag 201({subject_map}) ).
fn emitSubjectOnlyEnvelope(allocator: Allocator, subject_pairs: PairList) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();
    try w.writeTag(cbor.Tag.envelope);
    try w.writeTag(cbor.Tag.leaf);
    try emitMap(&w, subject_pairs);
    return w.toOwned();
}

/// Write an envelope with assertions:
///   tag 200( [ tag 201({subject_map}), [pred0, obj0], [pred1, obj1], ... ] )
fn emitEnvelope(allocator: Allocator, subject_pairs: PairList, assertion_pairs: PairList) ![]u8 {
    if (assertion_pairs.pairs.items.len == 0) {
        return emitSubjectOnlyEnvelope(allocator, subject_pairs);
    }

    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();
    try w.writeTag(cbor.Tag.envelope);
    try w.writeArrayHeader(1 + assertion_pairs.pairs.items.len);

    try w.writeTag(cbor.Tag.leaf);
    try emitMap(&w, subject_pairs);

    for (assertion_pairs.pairs.items) |p| {
        try w.writeArrayHeader(2);
        try w.writeText(p.key);
        try w.appendSlice(p.value);
    }
    return w.toOwned();
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
    const fv: u32 = if (db.dreamball_type != null or db.guilds.len > 0)
        protocol.FORMAT_VERSION_V2
    else
        protocol.FORMAT_VERSION;
    try subj.addText("type", type_str);
    try subj.addUint("format-version", fv);
    try subj.addText("stage", db.stage.toString());
    try subj.addBytes("identity", &db.identity);
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

    for (db.guilds) |fp| try asserts.addBytes("guild", &fp.bytes);
    for (db.contains) |fp| try asserts.addBytes("contains", &fp.bytes);
    for (db.derived_from) |fp| try asserts.addBytes("derived-from", &fp.bytes);

    // Signatures emitted last; predicate "signed" repeated per algorithm.
    for (db.signatures) |sig| {
        // Object: 2-text-array [alg, value_bytes]. Encode inline into bytes.
        var w = cbor.Writer.init(allocator);
        errdefer w.deinit();
        try w.writeArrayHeader(2);
        try w.writeText(sig.alg);
        try w.writeBytes(sig.value);
        const obj_bytes = try w.toOwned();
        try asserts.addRawOwned("signed", obj_bytes);
    }

    asserts.sort();

    return emitEnvelope(allocator, subj, asserts);
}

// ============================================================================
// Decoder (subject only — sufficient for verify/show v0)
// ============================================================================

/// Decode subject-only round-trip companion for `encodeDreamBall`. Reads the
/// subject map whether or not assertions follow.
pub fn decodeDreamBallSubject(bytes: []const u8) !protocol.DreamBall {
    var r = cbor.Reader.init(bytes);
    try r.expectTag(cbor.Tag.envelope);

    // Peek the next head — if it's tag 201 we have a subject-only envelope;
    // if it's an array, the first element is the tag-201 subject leaf.
    const save_cursor = r.cursor;
    const next_byte = if (r.cursor < r.bytes.len) r.bytes[r.cursor] else return error.Truncated;
    const next_major: u3 = @intCast(next_byte >> 5);

    if (next_major == 4) {
        // Array: read header, then the first element is the leaf.
        _ = try r.readHead(); // array header; length not needed for subject read
        try r.expectTag(cbor.Tag.leaf);
    } else {
        r.cursor = save_cursor;
        try r.expectTag(cbor.Tag.leaf);
    }

    const map_len = try r.readMapHeader();

    var out = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
    };

    var i: u64 = 0;
    while (i < map_len) : (i += 1) {
        const key = try r.readText();
        if (std.mem.eql(u8, key, "type")) {
            const t = try r.readText();
            if (std.mem.eql(u8, t, DREAMBALL_TYPE)) {
                // untyped — pass
            } else if (protocol.DreamBallType.fromWireString(t)) |dt| {
                out.dreamball_type = dt;
            } else {
                return error.WrongType;
            }
        } else if (std.mem.eql(u8, key, "format-version")) {
            const v = try r.readUint();
            if (v != protocol.FORMAT_VERSION and v != protocol.FORMAT_VERSION_V2) return error.UnsupportedVersion;
        } else if (std.mem.eql(u8, key, "stage")) {
            const s = try r.readText();
            out.stage = protocol.Stage.fromString(s) orelse return error.BadStage;
        } else if (std.mem.eql(u8, key, "identity")) {
            const b = try r.readBytes();
            if (b.len != 32) return error.BadIdentity;
            @memcpy(&out.identity, b);
        } else if (std.mem.eql(u8, key, "genesis-hash")) {
            const b = try r.readBytes();
            if (b.len != 32) return error.BadGenesis;
            @memcpy(&out.genesis_hash, b);
        } else if (std.mem.eql(u8, key, "revision")) {
            const v = try r.readUint();
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

/// Compute the byte length of the CBOR item starting at `bytes[start]`,
/// including the head and all nested content.
fn itemLen(bytes: []const u8, start: usize) !usize {
    if (start >= bytes.len) return error.Truncated;
    const b = bytes[start];
    const major: u3 = @intCast(b >> 5);
    const info: u5 = @intCast(b & 0x1F);

    // Head length by info value.
    const arg_len: usize = switch (info) {
        0...23 => 0,
        24 => 1,
        25 => 2,
        26 => 4,
        27 => 8,
        else => return error.UnsupportedType,
    };
    if (start + 1 + arg_len > bytes.len) return error.Truncated;

    // Decode the arg.
    const arg: u64 = switch (info) {
        0...23 => @as(u64, info),
        24 => @as(u64, bytes[start + 1]),
        25 => std.mem.readInt(u16, bytes[start + 1 ..][0..2], .big),
        26 => std.mem.readInt(u32, bytes[start + 1 ..][0..4], .big),
        27 => std.mem.readInt(u64, bytes[start + 1 ..][0..8], .big),
        else => unreachable,
    };

    const head_end = start + 1 + arg_len;

    return switch (major) {
        0, 1, 7 => head_end - start, // uint / negint / simple
        2, 3 => blk: { // byte string / text string
            const len: usize = @intCast(arg);
            if (head_end + len > bytes.len) return error.Truncated;
            break :blk (head_end - start) + len;
        },
        4 => blk: { // array
            var pos = head_end;
            var i: u64 = 0;
            while (i < arg) : (i += 1) {
                const sub = try itemLen(bytes, pos);
                pos += sub;
            }
            break :blk pos - start;
        },
        5 => blk: { // map
            var pos = head_end;
            var i: u64 = 0;
            while (i < arg) : (i += 1) {
                const k = try itemLen(bytes, pos);
                pos += k;
                const v = try itemLen(bytes, pos);
                pos += v;
            }
            break :blk pos - start;
        },
        6 => blk: { // tag — wraps one further item
            const inner = try itemLen(bytes, head_end);
            break :blk (head_end - start) + inner;
        },
    };
}

pub const StripError = error{
    Truncated,
    UnsupportedType,
    NotEnvelope,
    MalformedAssertion,
    OutOfMemory,
};

pub fn stripSignatures(allocator: std.mem.Allocator, bytes: []const u8) StripError!StripResult {
    var r = cbor.Reader.init(bytes);
    r.expectTag(cbor.Tag.envelope) catch return StripError.NotEnvelope;
    const body_start = r.cursor;

    const head = r.readHead() catch return StripError.Truncated;

    // Subject-only envelope: there are no assertions to strip. Return a copy.
    if (head.major != 4) {
        const copy = try allocator.dupe(u8, bytes);
        return .{
            .unsigned = copy,
            .signatures = try allocator.alloc(CapturedSignature, 0),
            .allocator = allocator,
        };
    }

    const element_count: u64 = head.arg;
    if (element_count == 0) return StripError.MalformedAssertion;

    // First element is the tag-201 subject leaf. Skip past it.
    const subject_start = r.cursor;
    const subject_len = itemLen(bytes, subject_start) catch return StripError.Truncated;
    r.cursor = subject_start + subject_len;

    var kept_ranges: std.ArrayList([2]usize) = .empty; // [start, end)
    defer kept_ranges.deinit(allocator);
    var captured: std.ArrayList(CapturedSignature) = .empty;
    errdefer captured.deinit(allocator);

    try kept_ranges.append(allocator, .{ subject_start, subject_start + subject_len });

    var i: u64 = 1;
    while (i < element_count) : (i += 1) {
        const elem_start = r.cursor;
        const elem_len = itemLen(bytes, elem_start) catch return StripError.Truncated;
        const elem_end = elem_start + elem_len;

        // Expect the element to be a 2-array [predicate_text, object].
        var ar = cbor.Reader.init(bytes[elem_start..elem_end]);
        const h = ar.readHead() catch return StripError.MalformedAssertion;
        if (h.major != 4 or h.arg != 2) return StripError.MalformedAssertion;

        const pred_start_rel = ar.cursor;
        const pred = ar.readText() catch return StripError.MalformedAssertion;
        _ = pred_start_rel;

        if (std.mem.eql(u8, pred, "signed")) {
            // Object shape: [alg_text, value_bytes]. Parse to capture.
            const obj_head = ar.readHead() catch return StripError.MalformedAssertion;
            if (obj_head.major != 4 or obj_head.arg != 2) return StripError.MalformedAssertion;
            const alg = ar.readText() catch return StripError.MalformedAssertion;
            const val = ar.readBytes() catch return StripError.MalformedAssertion;
            try captured.append(allocator, .{ .alg = alg, .value = val });
            // Do NOT add to kept_ranges — this assertion is stripped.
        } else {
            try kept_ranges.append(allocator, .{ elem_start, elem_end });
        }

        r.cursor = elem_end;
    }

    // Rebuild the envelope.
    const new_count = kept_ranges.items.len;
    var out = cbor.Writer.init(allocator);
    errdefer out.deinit();
    try out.writeTag(cbor.Tag.envelope);
    if (new_count == 1) {
        // Only the subject — emit as subject-only (no array wrapper) so the
        // canonical form matches what the encoder would have produced for a
        // DreamBall with signatures=[] and no other assertions.
        const r_subj = kept_ranges.items[0];
        try out.appendSlice(bytes[r_subj[0]..r_subj[1]]);
    } else {
        try out.writeArrayHeader(new_count);
        for (kept_ranges.items) |rr| {
            try out.appendSlice(bytes[rr[0]..rr[1]]);
        }
    }
    // silence unused warning on body_start
    _ = body_start;

    const unsigned = try out.toOwned();
    const sigs = try captured.toOwnedSlice(allocator);
    return .{ .unsigned = unsigned, .signatures = sigs, .allocator = allocator };
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
