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

pub const DREAMBALL_TYPE: []const u8 = "ball.dreamball";
pub const LOOK_TYPE: []const u8 = "ball.look";
pub const FEEL_TYPE: []const u8 = "ball.feel";
pub const ACT_TYPE: []const u8 = "ball.act";
pub const ASSET_TYPE: []const u8 = "ball.asset";
pub const SKILL_TYPE: []const u8 = "ball.skill";

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

// ─── ball.memory slot codec ─────────────────────────────────────────────────
//
// The memory slot is a first-class DreamBall slot (beside look/feel/act).
// Relocated here from envelope_v2.zig so `encodeDreamBall`/`decodeDreamBall`
// can attach/parse it directly without crossing the v2 import boundary.
// See docs/PROTOCOL.md §12.3.

pub fn encodeMemory(allocator: Allocator, m: protocol.Memory) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    const attribute_count: u64 = m.nodes.len + m.connections.len + @as(u64, if (m.last_updated != null) 1 else 0);
    try zbor.builder.writeArray(w, 1 + attribute_count);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.memory");
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    for (m.nodes) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "node");
        try writeMemoryNode(w, n);
    }
    for (m.connections) |c| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "connection");
        try writeMemoryConnection(w, c);
    }
    if (m.last_updated) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "last-updated");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
    return ai.toOwnedSlice();
}

fn writeMemoryNode(w: *std.Io.Writer, n: protocol.MemoryNode) !void {
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    var attribute_count: u64 = 0;
    if (n.content != null) attribute_count += 1;
    attribute_count += n.lookups.len;
    if (n.created != null) attribute_count += 1;
    if (n.last_recalled != null) attribute_count += 1;
    try zbor.builder.writeArray(w, 1 + attribute_count);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 3);
    try zbor.builder.writeTextString(w, "id");
    try zbor.builder.writeInt(w, @intCast(n.id));
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.memory-node");
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    if (n.content) |c| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "content");
        try zbor.builder.writeTextString(w, c);
    }
    for (n.lookups) |lk| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "lookup");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, lk.name);
        // Float: use 64-bit for simplicity. The protocol spec allows
        // half/single floats; we use f64 as the widest canonical form.
        try zbor.builder.writeFloat(w, lk.value);
    }
    if (n.created) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "created");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
    if (n.last_recalled) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "last-recalled");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
}

fn writeMemoryConnection(w: *std.Io.Writer, e: protocol.MemoryConnection) !void {
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    var attribute_count: u64 = 1; // strength
    if (e.label != null) attribute_count += 1;
    try zbor.builder.writeArray(w, 1 + attribute_count);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // dCBOR canonical order: len ascending, then lex for equal lengths.
    // Keys: "to"(2), "from"(4), "kind"(4), "type"(4), "format-version"(14).
    // At length 4, lex order is "from" < "kind" < "type".
    try zbor.builder.writeMap(w, 5);
    try zbor.builder.writeTextString(w, "to");
    try zbor.builder.writeInt(w, @intCast(e.to));
    try zbor.builder.writeTextString(w, "from");
    try zbor.builder.writeInt(w, @intCast(e.from));
    try zbor.builder.writeTextString(w, "kind");
    try zbor.builder.writeTextString(w, e.kind.toWireString());
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.memory-connection");
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "strength");
    try zbor.builder.writeFloat(w, e.strength);
    if (e.label) |lbl| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "label");
        try zbor.builder.writeTextString(w, lbl);
    }
}

/// Decode a `ball.memory` envelope produced by `encodeMemory`.
///
/// Mirrors the encoder exactly: an envelope whose attribute list carries
/// repeatable ("node", <MemoryNode envelope>) / ("connection",
/// <MemoryConnection envelope>) pairs plus an optional ("last-updated", …).
/// The node/connection attribute *values* are inline nested envelopes, so
/// they are consumed from the shared cursor via `readMemoryNode` /
/// `readMemoryConnection`. Nodes and connections accumulate into
/// `ArrayListUnmanaged`s (the file's Zig-0.16 idiom) and are returned as
/// owned slices. Memory carries floats (lookup value, connection strength)
/// so the canonicality gate is the float-allowing variant.
pub fn decodeMemory(allocator: Allocator, bytes: []const u8) !protocol.Memory {
    try dcbor.assertCanonicalAllowFloats(bytes);
    var cursor: usize = 0;
    const attr_count = try dcbor.readEnvelopeHeader(bytes, &cursor);
    try dcbor.skipCoreMap(bytes, &cursor);

    var nodes_list = std.ArrayListUnmanaged(protocol.MemoryNode).empty;
    defer nodes_list.deinit(allocator);
    var conns_list = std.ArrayListUnmanaged(protocol.MemoryConnection).empty;
    defer conns_list.deinit(allocator);
    var last_updated: ?i64 = null;

    var aii: u64 = 0;
    while (aii < attr_count) : (aii += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "node")) {
            const n = try readMemoryNode(allocator, bytes, &cursor);
            try nodes_list.append(allocator, n);
        } else if (std.mem.eql(u8, key, "connection")) {
            const c = try readMemoryConnection(bytes, &cursor);
            try conns_list.append(allocator, c);
        } else if (std.mem.eql(u8, key, "last-updated")) {
            dcbor.expectTag(bytes, &cursor, dcbor.Tag.epoch_time) catch |e| return dcbor.mapDecodeError(e);
            const ts = dcbor.readUint(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            last_updated = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .nodes = try nodes_list.toOwnedSlice(allocator),
        .connections = try conns_list.toOwnedSlice(allocator),
        .last_updated = last_updated,
    };
}

/// Consume one inline `ball.memory-node` envelope from the shared cursor.
/// The `lookups` slice is owned by `allocator`.
fn readMemoryNode(allocator: Allocator, bytes: []const u8, cursor: *usize) !protocol.MemoryNode {
    dcbor.expectTag(bytes, cursor, dcbor.Tag.envelope) catch |e| return dcbor.mapDecodeError(e);
    const array_count = dcbor.readArrayHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
    if (array_count == 0) return dcbor.DecodeError.MissingField;
    const attr_count = array_count - 1;

    // Core map: "id"(2), "type"(4), "format-version"(14)
    dcbor.expectTag(bytes, cursor, dcbor.Tag.leaf) catch |e| return dcbor.mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
    var id_opt: ?u64 = null;
    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, k, "id")) {
            id_opt = dcbor.readUint(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    var content: ?[]const u8 = null;
    var created: ?i64 = null;
    var last_recalled: ?i64 = null;
    var lookups_list = std.ArrayListUnmanaged(protocol.MemoryNode.LookupEntry).empty;
    defer lookups_list.deinit(allocator);

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "content")) {
            content = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "lookup")) {
            const inner_n = dcbor.readArrayHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            if (inner_n != 2) return dcbor.DecodeError.InvalidValue;
            const name = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            const value = dcbor.readAnyFloat(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            try lookups_list.append(allocator, .{ .name = name, .value = value });
        } else if (std.mem.eql(u8, key, "created")) {
            dcbor.expectTag(bytes, cursor, dcbor.Tag.epoch_time) catch |e| return dcbor.mapDecodeError(e);
            const ts = dcbor.readUint(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            created = @intCast(ts);
        } else if (std.mem.eql(u8, key, "last-recalled")) {
            dcbor.expectTag(bytes, cursor, dcbor.Tag.epoch_time) catch |e| return dcbor.mapDecodeError(e);
            const ts = dcbor.readUint(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            last_recalled = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .id = id_opt orelse return dcbor.DecodeError.MissingField,
        .content = content,
        .lookups = try lookups_list.toOwnedSlice(allocator),
        .created = created,
        .last_recalled = last_recalled,
    };
}

/// Consume one inline `ball.memory-connection` envelope from the shared cursor.
fn readMemoryConnection(bytes: []const u8, cursor: *usize) !protocol.MemoryConnection {
    dcbor.expectTag(bytes, cursor, dcbor.Tag.envelope) catch |e| return dcbor.mapDecodeError(e);
    const array_count = dcbor.readArrayHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
    if (array_count == 0) return dcbor.DecodeError.MissingField;
    const attr_count = array_count - 1;

    // Core map: "to"(2), "from"(4), "kind"(4), "type"(4), "format-version"(14)
    dcbor.expectTag(bytes, cursor, dcbor.Tag.leaf) catch |e| return dcbor.mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
    var to_opt: ?u64 = null;
    var from_opt: ?u64 = null;
    var kind_opt: ?protocol.MemoryConnectionKind = null;
    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, k, "to")) {
            to_opt = dcbor.readUint(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else if (std.mem.eql(u8, k, "from")) {
            from_opt = dcbor.readUint(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else if (std.mem.eql(u8, k, "kind")) {
            const s = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            if (std.mem.eql(u8, s, "semantic")) {
                kind_opt = .semantic;
            } else if (std.mem.eql(u8, s, "emotional")) {
                kind_opt = .emotional;
            } else if (std.mem.eql(u8, s, "temporal")) {
                kind_opt = .temporal;
            } else if (std.mem.eql(u8, s, "other")) {
                kind_opt = .other;
            } else return dcbor.DecodeError.InvalidValue;
        } else {
            dcbor.skipItem(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    var strength: ?f64 = null;
    var label: ?[]const u8 = null;
    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "strength")) {
            strength = dcbor.readAnyFloat(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "label")) {
            label = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .from = from_opt orelse return dcbor.DecodeError.MissingField,
        .to = to_opt orelse return dcbor.DecodeError.MissingField,
        .kind = kind_opt orelse return dcbor.DecodeError.MissingField,
        .strength = strength orelse return dcbor.DecodeError.MissingField,
        .label = label,
    };
}

// ─── ball.knowledge-graph slot codec (§12.4) ────────────────────────────────
//
// First-class DreamBall slot. Encoder relocated here from envelope_v2.zig;
// decoder written to mirror it. Triples ride as repeatable ("triple",
// [from, label, to]) attribute pairs; an optional ("source", text) follows.

pub fn encodeKnowledgeGraph(allocator: Allocator, kg: protocol.KnowledgeGraph) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = kg.triples.len;
    if (kg.source != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.knowledge-graph");
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    for (kg.triples) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "triple");
        try zbor.builder.writeArray(w, 3);
        try zbor.builder.writeTextString(w, t.from);
        try zbor.builder.writeTextString(w, t.label);
        try zbor.builder.writeTextString(w, t.to);
    }
    if (kg.source) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "source");
        try zbor.builder.writeTextString(w, s);
    }
    return ai.toOwnedSlice();
}

/// Decode a `ball.knowledge-graph` envelope produced by `encodeKnowledgeGraph`.
/// Triple string fields are slices into `bytes` (must outlive the result), the
/// same lifetime discipline as `decodeMemory`. No floats → plain canonical gate.
pub fn decodeKnowledgeGraph(allocator: Allocator, bytes: []const u8) !protocol.KnowledgeGraph {
    try dcbor.assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try dcbor.readEnvelopeHeader(bytes, &cursor);
    try dcbor.skipCoreMap(bytes, &cursor);

    var triples_list = std.ArrayListUnmanaged(protocol.Triple).empty;
    defer triples_list.deinit(allocator);
    var source: ?[]const u8 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "triple")) {
            const inner_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            if (inner_n != 3) return dcbor.DecodeError.InvalidValue;
            const from = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            const label = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            const to = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            try triples_list.append(allocator, .{ .from = from, .label = label, .to = to });
        } else if (std.mem.eql(u8, key, "source")) {
            source = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .triples = try triples_list.toOwnedSlice(allocator),
        .source = source,
    };
}

// ─── ball.emotional-register slot codec (§12.5) ──────────────────────────────
//
// First-class DreamBall slot. Encoder relocated here from envelope_v2.zig;
// decoder written to mirror it. Each axis rides as ("axis", {max,min,name,value})
// — the inner map keys are emitted in dCBOR canonical order (len asc, lex). Axis
// values are floats (§12.2 exception) → the float-allowing canonical gate.

pub fn encodeEmotionalRegister(allocator: Allocator, er: protocol.EmotionalRegister) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = er.axes.len;
    if (er.observed_at != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.emotional-register");
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    for (er.axes) |ax| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "axis");
        // Keys sorted (len asc, lex): "max"(3) < "min"(3) < "name"(4) < "value"(5).
        try zbor.builder.writeMap(w, 4);
        try zbor.builder.writeTextString(w, "max");
        try zbor.builder.writeFloat(w, ax.max);
        try zbor.builder.writeTextString(w, "min");
        try zbor.builder.writeFloat(w, ax.min);
        try zbor.builder.writeTextString(w, "name");
        try zbor.builder.writeTextString(w, ax.name);
        try zbor.builder.writeTextString(w, "value");
        try zbor.builder.writeFloat(w, ax.value);
    }
    if (er.observed_at) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "observed-at");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
    return ai.toOwnedSlice();
}

/// Decode a `ball.emotional-register` envelope produced by
/// `encodeEmotionalRegister`. Axis names are slices into `bytes`.
pub fn decodeEmotionalRegister(allocator: Allocator, bytes: []const u8) !protocol.EmotionalRegister {
    try dcbor.assertCanonicalAllowFloats(bytes);
    var cursor: usize = 0;
    const attr_count = try dcbor.readEnvelopeHeader(bytes, &cursor);
    try dcbor.skipCoreMap(bytes, &cursor);

    var axes_list = std.ArrayListUnmanaged(protocol.EmotionalAxis).empty;
    defer axes_list.deinit(allocator);
    var observed_at: ?i64 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "axis")) {
            const map_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            var name_opt: ?[]const u8 = null;
            var value_opt: ?f64 = null;
            var min: f64 = 0.0;
            var max: f64 = 1.0;
            var mi: u64 = 0;
            while (mi < map_n) : (mi += 1) {
                const mk = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
                if (std.mem.eql(u8, mk, "name")) {
                    name_opt = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
                } else if (std.mem.eql(u8, mk, "value")) {
                    value_opt = dcbor.readAnyFloat(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
                } else if (std.mem.eql(u8, mk, "min")) {
                    min = dcbor.readAnyFloat(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
                } else if (std.mem.eql(u8, mk, "max")) {
                    max = dcbor.readAnyFloat(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
                } else {
                    dcbor.skipItem(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
                }
            }
            try axes_list.append(allocator, .{
                .name = name_opt orelse return dcbor.DecodeError.MissingField,
                .value = value_opt orelse return dcbor.DecodeError.MissingField,
                .min = min,
                .max = max,
            });
        } else if (std.mem.eql(u8, key, "observed-at")) {
            dcbor.expectTag(bytes, &cursor, dcbor.Tag.epoch_time) catch |e| return dcbor.mapDecodeError(e);
            const ts = dcbor.readUint(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            observed_at = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .axes = try axes_list.toOwnedSlice(allocator),
        .observed_at = observed_at,
    };
}

// ─── ball.interaction-set slot codec (§12.6) ────────────────────────────────
//
// First-class DreamBall slot — REPEATABLE on the DreamBall (TS
// `'interaction-set'?: InteractionSet[]`). No prior encoder existed; both the
// encoder and decoder are written here, mirroring `encodeMemory`/`decodeMemory`.
// The 16-byte `set-id` rides in the core map; interactions ride as repeatable
// ("interaction", <ball.interaction envelope>) attribute pairs. No floats.

pub fn encodeInteractionSet(allocator: Allocator, is: protocol.InteractionSet) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    const ac: u64 = is.interactions.len + @as(u64, if (is.created != null) 1 else 0);
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted (len asc, lex): "type"(4), "set-id"(6), "format-version"(14).
    try zbor.builder.writeMap(w, 3);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.interaction-set");
    try zbor.builder.writeTextString(w, "set-id");
    try zbor.builder.writeByteString(w, &is.set_id);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    for (is.interactions) |it| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "interaction");
        try writeInteraction(w, it);
    }
    if (is.created) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "created");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
    return ai.toOwnedSlice();
}

fn writeInteraction(w: *std.Io.Writer, it: protocol.Interaction) !void {
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    var attribute_count: u64 = 0;
    if (it.content != null) attribute_count += 1;
    if (it.outcome != null) attribute_count += 1;
    if (it.timestamp != null) attribute_count += 1;
    try zbor.builder.writeArray(w, 1 + attribute_count);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted (len asc, lex): "kind"(4) < "turn"(4) < "type"(4) < "actor"(5) < "format-version"(14).
    try zbor.builder.writeMap(w, 5);
    try zbor.builder.writeTextString(w, "kind");
    try zbor.builder.writeTextString(w, it.kindString());
    try zbor.builder.writeTextString(w, "turn");
    try zbor.builder.writeInt(w, @intCast(it.turn));
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.interaction");
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &it.actor.bytes);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    // Attribute pairs (array elements — order is not canonicality-checked, but
    // we emit them sorted for tidiness): "content"(7), "outcome"(7), "timestamp"(9).
    if (it.content) |c| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "content");
        try zbor.builder.writeTextString(w, c);
    }
    if (it.outcome) |o| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "outcome");
        try zbor.builder.writeTextString(w, o);
    }
    if (it.timestamp) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "timestamp");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
}

/// Decode a `ball.interaction-set` envelope produced by `encodeInteractionSet`.
/// Interaction string fields are slices into `bytes`.
pub fn decodeInteractionSet(allocator: Allocator, bytes: []const u8) !protocol.InteractionSet {
    try dcbor.assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try dcbor.readEnvelopeHeader(bytes, &cursor);

    // Core map carries the 16-byte set-id.
    dcbor.expectTag(bytes, &cursor, dcbor.Tag.leaf) catch |e| return dcbor.mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
    var set_id_opt: ?[16]u8 = null;
    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, k, "set-id")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            if (b.len != 16) return dcbor.DecodeError.InvalidValue;
            var sid: [16]u8 = undefined;
            @memcpy(&sid, b);
            set_id_opt = sid;
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    var inter_list = std.ArrayListUnmanaged(protocol.Interaction).empty;
    defer inter_list.deinit(allocator);
    var created: ?i64 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "interaction")) {
            const it = try readInteraction(bytes, &cursor);
            try inter_list.append(allocator, it);
        } else if (std.mem.eql(u8, key, "created")) {
            dcbor.expectTag(bytes, &cursor, dcbor.Tag.epoch_time) catch |e| return dcbor.mapDecodeError(e);
            const ts = dcbor.readUint(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            created = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .set_id = set_id_opt orelse return dcbor.DecodeError.MissingField,
        .interactions = try inter_list.toOwnedSlice(allocator),
        .created = created,
    };
}

/// Consume one inline `ball.interaction` envelope from the shared cursor.
fn readInteraction(bytes: []const u8, cursor: *usize) !protocol.Interaction {
    dcbor.expectTag(bytes, cursor, dcbor.Tag.envelope) catch |e| return dcbor.mapDecodeError(e);
    const array_count = dcbor.readArrayHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
    if (array_count == 0) return dcbor.DecodeError.MissingField;
    const attr_count = array_count - 1;

    dcbor.expectTag(bytes, cursor, dcbor.Tag.leaf) catch |e| return dcbor.mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
    var turn_opt: ?u32 = null;
    var actor_opt: ?Fingerprint = null;
    var kind_opt: ?protocol.InteractionKind = null;
    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, k, "turn")) {
            turn_opt = @intCast(dcbor.readUint(bytes, cursor) catch |e| return dcbor.mapDecodeError(e));
        } else if (std.mem.eql(u8, k, "actor")) {
            const b = dcbor.readBytes(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            if (b.len != 32) return dcbor.DecodeError.InvalidValue;
            var fp: Fingerprint = undefined;
            @memcpy(&fp.bytes, b);
            actor_opt = fp;
        } else if (std.mem.eql(u8, k, "kind")) {
            const s = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            if (std.mem.eql(u8, s, "speak")) {
                kind_opt = .speak;
            } else if (std.mem.eql(u8, s, "listen")) {
                kind_opt = .listen;
            } else if (std.mem.eql(u8, s, "act")) {
                kind_opt = .act;
            } else if (std.mem.eql(u8, s, "receive")) {
                kind_opt = .receive;
            } else return dcbor.DecodeError.InvalidValue;
        } else {
            dcbor.skipItem(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    var content: ?[]const u8 = null;
    var outcome: ?[]const u8 = null;
    var timestamp: ?i64 = null;
    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "content")) {
            content = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "outcome")) {
            outcome = dcbor.readText(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "timestamp")) {
            dcbor.expectTag(bytes, cursor, dcbor.Tag.epoch_time) catch |e| return dcbor.mapDecodeError(e);
            const ts = dcbor.readUint(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
            timestamp = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .turn = turn_opt orelse return dcbor.DecodeError.MissingField,
        .actor = actor_opt orelse return dcbor.DecodeError.MissingField,
        .kind = kind_opt orelse return dcbor.DecodeError.MissingField,
        .content = content,
        .timestamp = timestamp,
        .outcome = outcome,
    };
}

// ─── ball.guild-policy slot codec (§12.7) ───────────────────────────────────
//
// First-class DreamBall slot, attached as a `guild-policy` assertion (distinct
// from the policy map embedded inside a Guild envelope by `encodeGuild`). No
// standalone encoder existed; both encoder and decoder are written here per the
// §12.7 wire shape: repeatable ("public"|"guild-only"|"admin-only", text) pairs
// plus an optional ("note", text). No floats.

pub fn encodeGuildPolicy(allocator: Allocator, p: protocol.GuildPolicy) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = p.public.len + p.guild_only.len + p.admin_only.len;
    if (p.note != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.guild-policy");
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    for (p.public) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "public");
        try zbor.builder.writeTextString(w, s);
    }
    for (p.guild_only) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "guild-only");
        try zbor.builder.writeTextString(w, s);
    }
    for (p.admin_only) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "admin-only");
        try zbor.builder.writeTextString(w, s);
    }
    if (p.note) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "note");
        try zbor.builder.writeTextString(w, n);
    }
    return ai.toOwnedSlice();
}

/// Decode a `ball.guild-policy` envelope produced by `encodeGuildPolicy`. Slot
/// strings are slices into `bytes`; the three slot lists are owned by `allocator`.
pub fn decodeGuildPolicy(allocator: Allocator, bytes: []const u8) !protocol.GuildPolicy {
    try dcbor.assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try dcbor.readEnvelopeHeader(bytes, &cursor);
    try dcbor.skipCoreMap(bytes, &cursor);

    var public_list = std.ArrayListUnmanaged([]const u8).empty;
    defer public_list.deinit(allocator);
    var guild_list = std.ArrayListUnmanaged([]const u8).empty;
    defer guild_list.deinit(allocator);
    var admin_list = std.ArrayListUnmanaged([]const u8).empty;
    defer admin_list.deinit(allocator);
    var note: ?[]const u8 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (arr_n != 2) return dcbor.DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        if (std.mem.eql(u8, key, "public")) {
            const s = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            try public_list.append(allocator, s);
        } else if (std.mem.eql(u8, key, "guild-only")) {
            const s = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            try guild_list.append(allocator, s);
        } else if (std.mem.eql(u8, key, "admin-only")) {
            const s = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
            try admin_list.append(allocator, s);
        } else if (std.mem.eql(u8, key, "note")) {
            note = dcbor.readText(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return dcbor.mapDecodeError(e);
        }
    }

    return .{
        .public = try public_list.toOwnedSlice(allocator),
        .guild_only = try guild_list.toOwnedSlice(allocator),
        .admin_only = try admin_list.toOwnedSlice(allocator),
        .note = note,
    };
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
    if (db.memory) |m| {
        const bytes = try encodeMemory(allocator, m);
        try asserts.addRawOwned("memory", bytes);
    }
    if (db.knowledge_graph) |kg| {
        const bytes = try encodeKnowledgeGraph(allocator, kg);
        try asserts.addRawOwned("knowledge-graph", bytes);
    }
    if (db.emotional_register) |er| {
        const bytes = try encodeEmotionalRegister(allocator, er);
        try asserts.addRawOwned("emotional-register", bytes);
    }
    // Repeatable: one "interaction-set" assertion per element. PairList.sort is
    // stable, so multiple equal keys keep their insertion order on the wire.
    for (db.interaction_sets) |is| {
        const bytes = try encodeInteractionSet(allocator, is);
        try asserts.addRawOwned("interaction-set", bytes);
    }
    if (db.policy) |p| {
        const bytes = try encodeGuildPolicy(allocator, p);
        try asserts.addRawOwned("guild-policy", bytes);
    }

    if (db.field_kind) |fk| try asserts.addText("field-kind", fk);
    if (db.archiform_fp) |afp| try asserts.addBytes("archiform-fp", &afp);
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
    // Allow floats: a DreamBall may carry a `memory` slot, whose lookup
    // values and connection strengths are floats under the §12.2 exception.
    // The whole-envelope gate runs over those bytes even in subject-only mode.
    try dcbor.verifyCanonicalAllowFloats(bytes);

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
// Scope note: this decoder fully decodes the top-level DreamBall, Look,
// Feel, Act, Asset, and Skill envelopes (plus archiform-fp and the
// scalar/list attributes). Memory / knowledge-graph / emotional-register
// / interaction-set / guild-policy assertions are NOT decoded — they hit
// the `else` branch of the assertion walk below and are skipped, i.e.
// dropped from the typed struct (there is no `raw_assertions` passthrough
// field; an earlier comment claiming one was stale). Finishing them is
// tracked as Dreamball-m97 and is done by extending
// `schemas/root-2.0.0.json` and regenerating via `bun run codegen`
// (the JSON-Schema-canonical pipeline, D-018/D-030) — NOT by hand-adding
// `decodeXFromEnvelope` functions here.
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
    // Allow floats: the `memory` slot carries float lookup values and
    // connection strengths under the §12.2 exception, embedded inline in the
    // DreamBall envelope. look/feel/act carry no floats, so this only widens
    // acceptance for the float-bearing memory assertion.
    try dcbor.verifyCanonicalAllowFloats(env_bytes);

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
    var interaction_sets: std.ArrayList(protocol.InteractionSet) = .empty;
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
        } else if (std.mem.eql(u8, pred, "memory")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            out.memory = try decodeMemory(arena, sub);
        } else if (std.mem.eql(u8, pred, "knowledge-graph")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            out.knowledge_graph = try decodeKnowledgeGraph(arena, sub);
        } else if (std.mem.eql(u8, pred, "emotional-register")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            out.emotional_register = try decodeEmotionalRegister(arena, sub);
        } else if (std.mem.eql(u8, pred, "interaction-set")) {
            // Repeatable — append each decoded set in wire order.
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            try interaction_sets.append(arena, try decodeInteractionSet(arena, sub));
        } else if (std.mem.eql(u8, pred, "guild-policy")) {
            const len = dcbor.itemLen(env_bytes, cursor) catch return error.Truncated;
            const sub = env_bytes[cursor .. cursor + len];
            cursor += len;
            out.policy = try decodeGuildPolicy(arena, sub);
        } else if (std.mem.eql(u8, pred, "archiform-fp")) {
            // FR5 / Story 2.3 — round-trip the genesis envelope's
            // archiform_fp attribute. 32-byte blake3 of the archiform
            // schema body; immutable for the ball's lifetime per D-017.
            const b = try readBytes(env_bytes, &cursor);
            if (b.len != 32) return error.BadArchiformFp;
            var afp: [32]u8 = undefined;
            @memcpy(&afp, b);
            out.archiform_fp = afp;
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
    out.interaction_sets = try interaction_sets.toOwnedSlice(arena);
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

test "encodeMemory produces well-formed envelope" {
    const allocator = std.testing.allocator;
    const nodes = [_]protocol.MemoryNode{
        .{ .id = 1, .content = "First memory" },
        .{ .id = 2, .content = "Second memory" },
    };
    const connections = [_]protocol.MemoryConnection{
        .{ .from = 1, .to = 2, .kind = .temporal, .strength = 0.8 },
    };
    const m: protocol.Memory = .{ .nodes = &nodes, .connections = &connections };
    const bytes = try encodeMemory(allocator, m);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "First memory") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "temporal") != null);
}

test "encodeMemory -> decodeMemory round-trip" {
    const allocator = std.testing.allocator;
    const lookups = [_]protocol.MemoryNode.LookupEntry{
        .{ .name = "emotional", .value = 0.75 },
        .{ .name = "recency", .value = 0.5 },
    };
    const nodes = [_]protocol.MemoryNode{
        .{
            .id = 7,
            .content = "A vivid recollection",
            .lookups = &lookups,
            .created = 1_700_000_000,
            .last_recalled = 1_700_000_500,
        },
        .{ .id = 9 }, // minimal node
    };
    const connections = [_]protocol.MemoryConnection{
        .{ .from = 7, .to = 9, .kind = .emotional, .strength = 0.42, .label = "echoes" },
    };
    const m: protocol.Memory = .{
        .nodes = &nodes,
        .connections = &connections,
        .last_updated = 1_700_000_999,
    };

    const bytes = try encodeMemory(allocator, m);
    defer allocator.free(bytes);

    const got = try decodeMemory(allocator, bytes);
    defer {
        for (got.nodes) |n| allocator.free(n.lookups);
        allocator.free(got.nodes);
        allocator.free(got.connections);
    }

    // Nodes
    try std.testing.expectEqual(@as(usize, 2), got.nodes.len);
    try std.testing.expectEqual(@as(u64, 7), got.nodes[0].id);
    try std.testing.expectEqualStrings("A vivid recollection", got.nodes[0].content.?);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), got.nodes[0].created.?);
    try std.testing.expectEqual(@as(i64, 1_700_000_500), got.nodes[0].last_recalled.?);
    try std.testing.expectEqual(@as(usize, 2), got.nodes[0].lookups.len);
    try std.testing.expectEqualStrings("emotional", got.nodes[0].lookups[0].name);
    try std.testing.expectEqual(@as(f64, 0.75), got.nodes[0].lookups[0].value);
    try std.testing.expectEqualStrings("recency", got.nodes[0].lookups[1].name);
    try std.testing.expectEqual(@as(f64, 0.5), got.nodes[0].lookups[1].value);

    try std.testing.expectEqual(@as(u64, 9), got.nodes[1].id);
    try std.testing.expect(got.nodes[1].content == null);
    try std.testing.expectEqual(@as(usize, 0), got.nodes[1].lookups.len);
    try std.testing.expect(got.nodes[1].created == null);
    try std.testing.expect(got.nodes[1].last_recalled == null);

    // Connections
    try std.testing.expectEqual(@as(usize, 1), got.connections.len);
    try std.testing.expectEqual(@as(u64, 7), got.connections[0].from);
    try std.testing.expectEqual(@as(u64, 9), got.connections[0].to);
    try std.testing.expectEqual(protocol.MemoryConnectionKind.emotional, got.connections[0].kind);
    try std.testing.expectEqual(@as(f64, 0.42), got.connections[0].strength);
    try std.testing.expectEqualStrings("echoes", got.connections[0].label.?);

    // Top-level
    try std.testing.expectEqual(@as(i64, 1_700_000_999), got.last_updated.?);
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

test "decodeDreamBall round-trips the memory slot" {
    // Regression for the memory-slot wiring: `DreamBall.memory` must
    // encode/decode inline through `encodeDreamBall`/`decodeDreamBall`
    // exactly like look/feel/act.
    const gpa = std.testing.allocator;
    var arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();

    const lookups = [_]protocol.MemoryNode.LookupEntry{
        .{ .name = "emotional", .value = 0.9 },
    };
    const nodes = [_]protocol.MemoryNode{
        .{ .id = 1, .content = "the first dream", .lookups = &lookups, .created = 1_700_000_000 },
        .{ .id = 2, .content = "the second dream" },
    };
    const connections = [_]protocol.MemoryConnection{
        .{ .from = 1, .to = 2, .kind = .temporal, .strength = 0.6, .label = "then" },
    };
    const memory = protocol.Memory{
        .nodes = &nodes,
        .connections = &connections,
        .last_updated = 1_700_000_999,
    };

    const db = protocol.DreamBall{
        .stage = .dreamball,
        .dreamball_type = .agent,
        .identity = [_]u8{3} ** 32,
        .genesis_hash = [_]u8{4} ** 32,
        .revision = 1,
        .memory = memory,
    };

    const bytes = try encodeDreamBall(gpa, db);
    defer gpa.free(bytes);

    const decoded = try decodeDreamBall(arena, bytes);
    try std.testing.expect(decoded.memory != null);
    const m = decoded.memory.?;
    try std.testing.expectEqual(@as(usize, 2), m.nodes.len);
    try std.testing.expectEqual(@as(u64, 1), m.nodes[0].id);
    try std.testing.expectEqualStrings("the first dream", m.nodes[0].content.?);
    try std.testing.expectEqual(@as(usize, 1), m.nodes[0].lookups.len);
    try std.testing.expectEqualStrings("emotional", m.nodes[0].lookups[0].name);
    try std.testing.expectEqual(@as(f64, 0.9), m.nodes[0].lookups[0].value);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), m.nodes[0].created.?);
    try std.testing.expectEqual(@as(usize, 1), m.connections.len);
    try std.testing.expectEqual(@as(u64, 1), m.connections[0].from);
    try std.testing.expectEqual(@as(u64, 2), m.connections[0].to);
    try std.testing.expectEqual(protocol.MemoryConnectionKind.temporal, m.connections[0].kind);
    try std.testing.expectEqual(@as(f64, 0.6), m.connections[0].strength);
    try std.testing.expectEqualStrings("then", m.connections[0].label.?);
    try std.testing.expectEqual(@as(i64, 1_700_000_999), m.last_updated.?);
}

// ─── knowledge-graph slot ────────────────────────────────────────────────────

test "encodeKnowledgeGraph emits triples" {
    const allocator = std.testing.allocator;
    const triples = [_]protocol.Triple{
        .{ .from = "curiosity", .label = "inclines-toward", .to = "new-things" },
    };
    const kg: protocol.KnowledgeGraph = .{ .triples = &triples, .source = "test" };
    const bytes = try encodeKnowledgeGraph(allocator, kg);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "curiosity") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "inclines-toward") != null);
}

test "encodeKnowledgeGraph -> decodeKnowledgeGraph round-trip" {
    const allocator = std.testing.allocator;
    const triples = [_]protocol.Triple{
        .{ .from = "curiosity", .label = "inclines-toward", .to = "new-things" },
        .{ .from = "haiku", .label = "requires", .to = "5-7-5 syllables" },
    };
    const kg: protocol.KnowledgeGraph = .{ .triples = &triples, .source = "hand-curated v0" };
    const bytes = try encodeKnowledgeGraph(allocator, kg);
    defer allocator.free(bytes);

    const got = try decodeKnowledgeGraph(allocator, bytes);
    defer allocator.free(got.triples);
    try std.testing.expectEqual(@as(usize, 2), got.triples.len);
    try std.testing.expectEqualStrings("curiosity", got.triples[0].from);
    try std.testing.expectEqualStrings("inclines-toward", got.triples[0].label);
    try std.testing.expectEqualStrings("new-things", got.triples[0].to);
    try std.testing.expectEqualStrings("haiku", got.triples[1].from);
    try std.testing.expectEqualStrings("5-7-5 syllables", got.triples[1].to);
    try std.testing.expectEqualStrings("hand-curated v0", got.source.?);

    // Minimal (no triples, no source).
    const empty: protocol.KnowledgeGraph = .{};
    const eb = try encodeKnowledgeGraph(allocator, empty);
    defer allocator.free(eb);
    const eg = try decodeKnowledgeGraph(allocator, eb);
    defer allocator.free(eg.triples);
    try std.testing.expectEqual(@as(usize, 0), eg.triples.len);
    try std.testing.expect(eg.source == null);
}

// ─── emotional-register slot ─────────────────────────────────────────────────

test "encodeEmotionalRegister -> decodeEmotionalRegister round-trip" {
    const allocator = std.testing.allocator;
    const axes = [_]protocol.EmotionalAxis{
        .{ .name = "curiosity", .value = 0.82 },
        .{ .name = "warmth", .value = 0.55, .min = -1.0, .max = 1.0 },
    };
    const er: protocol.EmotionalRegister = .{ .axes = &axes, .observed_at = 1_700_000_321 };
    const bytes = try encodeEmotionalRegister(allocator, er);
    defer allocator.free(bytes);

    const got = try decodeEmotionalRegister(allocator, bytes);
    defer allocator.free(got.axes);
    try std.testing.expectEqual(@as(usize, 2), got.axes.len);
    try std.testing.expectEqualStrings("curiosity", got.axes[0].name);
    try std.testing.expectEqual(@as(f64, 0.82), got.axes[0].value);
    try std.testing.expectEqual(@as(f64, 0.0), got.axes[0].min);
    try std.testing.expectEqual(@as(f64, 1.0), got.axes[0].max);
    try std.testing.expectEqualStrings("warmth", got.axes[1].name);
    try std.testing.expectEqual(@as(f64, 0.55), got.axes[1].value);
    try std.testing.expectEqual(@as(f64, -1.0), got.axes[1].min);
    try std.testing.expectEqual(@as(i64, 1_700_000_321), got.observed_at.?);

    // Minimal.
    const empty: protocol.EmotionalRegister = .{};
    const eb = try encodeEmotionalRegister(allocator, empty);
    defer allocator.free(eb);
    const eg = try decodeEmotionalRegister(allocator, eb);
    defer allocator.free(eg.axes);
    try std.testing.expectEqual(@as(usize, 0), eg.axes.len);
    try std.testing.expect(eg.observed_at == null);
}

// ─── interaction-set slot ────────────────────────────────────────────────────

test "encodeInteractionSet -> decodeInteractionSet round-trip" {
    const allocator = std.testing.allocator;
    const interactions = [_]protocol.Interaction{
        .{
            .turn = 1,
            .actor = .{ .bytes = [_]u8{0xAA} ** 32 },
            .kind = .speak,
            .content = "hello there",
            .timestamp = 1_700_000_100,
            .outcome = "acknowledged",
        },
        .{ .turn = 2, .actor = .{ .bytes = [_]u8{0xBB} ** 32 }, .kind = .listen },
    };
    const is: protocol.InteractionSet = .{
        .set_id = [_]u8{0x11} ** 16,
        .interactions = &interactions,
        .created = 1_700_000_999,
    };
    const bytes = try encodeInteractionSet(allocator, is);
    defer allocator.free(bytes);

    const got = try decodeInteractionSet(allocator, bytes);
    defer allocator.free(got.interactions);
    try std.testing.expectEqualSlices(u8, &([_]u8{0x11} ** 16), &got.set_id);
    try std.testing.expectEqual(@as(usize, 2), got.interactions.len);
    try std.testing.expectEqual(@as(u32, 1), got.interactions[0].turn);
    try std.testing.expectEqualSlices(u8, &([_]u8{0xAA} ** 32), &got.interactions[0].actor.bytes);
    try std.testing.expectEqual(protocol.InteractionKind.speak, got.interactions[0].kind);
    try std.testing.expectEqualStrings("hello there", got.interactions[0].content.?);
    try std.testing.expectEqual(@as(i64, 1_700_000_100), got.interactions[0].timestamp.?);
    try std.testing.expectEqualStrings("acknowledged", got.interactions[0].outcome.?);
    try std.testing.expectEqual(@as(u32, 2), got.interactions[1].turn);
    try std.testing.expectEqual(protocol.InteractionKind.listen, got.interactions[1].kind);
    try std.testing.expect(got.interactions[1].content == null);
    try std.testing.expect(got.interactions[1].outcome == null);
    try std.testing.expectEqual(@as(i64, 1_700_000_999), got.created.?);

    // Minimal (no interactions, no created).
    const empty: protocol.InteractionSet = .{ .set_id = [_]u8{0x22} ** 16 };
    const eb = try encodeInteractionSet(allocator, empty);
    defer allocator.free(eb);
    const eg = try decodeInteractionSet(allocator, eb);
    defer allocator.free(eg.interactions);
    try std.testing.expectEqual(@as(usize, 0), eg.interactions.len);
    try std.testing.expect(eg.created == null);
}

// ─── guild-policy slot ───────────────────────────────────────────────────────

test "encodeGuildPolicy -> decodeGuildPolicy round-trip" {
    const allocator = std.testing.allocator;
    const p: protocol.GuildPolicy = .{ .note = "default v2 policy" };
    const bytes = try encodeGuildPolicy(allocator, p);
    defer allocator.free(bytes);

    const got = try decodeGuildPolicy(allocator, bytes);
    defer {
        allocator.free(got.public);
        allocator.free(got.guild_only);
        allocator.free(got.admin_only);
    }
    try std.testing.expectEqual(@as(usize, 2), got.public.len);
    try std.testing.expectEqualStrings("look", got.public[0]);
    try std.testing.expectEqualStrings("thumbnail", got.public[1]);
    try std.testing.expectEqual(@as(usize, 4), got.guild_only.len);
    try std.testing.expectEqualStrings("memory", got.guild_only[0]);
    try std.testing.expectEqualStrings("interaction-set", got.guild_only[3]);
    try std.testing.expectEqual(@as(usize, 1), got.admin_only.len);
    try std.testing.expectEqualStrings("secret", got.admin_only[0]);
    try std.testing.expectEqualStrings("default v2 policy", got.note.?);
}

// ─── all four slots through decodeDreamBall ──────────────────────────────────

test "decodeDreamBall round-trips knowledge-graph / emotional-register / interaction-set / guild-policy" {
    const gpa = std.testing.allocator;
    var arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();

    const triples = [_]protocol.Triple{
        .{ .from = "curiosity", .label = "inclines-toward", .to = "new-things" },
    };
    const axes = [_]protocol.EmotionalAxis{
        .{ .name = "curiosity", .value = 0.82 },
    };
    const interactions = [_]protocol.Interaction{
        .{ .turn = 1, .actor = .{ .bytes = [_]u8{0xCC} ** 32 }, .kind = .act, .content = "did a thing" },
    };
    const sets = [_]protocol.InteractionSet{
        .{ .set_id = [_]u8{0x33} ** 16, .interactions = &interactions, .created = 1_700_000_500 },
        .{ .set_id = [_]u8{0x44} ** 16 },
    };

    const db = protocol.DreamBall{
        .stage = .dreamball,
        .dreamball_type = .agent,
        .identity = [_]u8{5} ** 32,
        .genesis_hash = [_]u8{6} ** 32,
        .revision = 1,
        .knowledge_graph = .{ .triples = &triples, .source = "v0" },
        .emotional_register = .{ .axes = &axes, .observed_at = 1_700_000_321 },
        .interaction_sets = &sets,
        .policy = .{ .note = "p" },
    };

    const bytes = try encodeDreamBall(gpa, db);
    defer gpa.free(bytes);

    const decoded = try decodeDreamBall(arena, bytes);

    try std.testing.expect(decoded.knowledge_graph != null);
    try std.testing.expectEqual(@as(usize, 1), decoded.knowledge_graph.?.triples.len);
    try std.testing.expectEqualStrings("inclines-toward", decoded.knowledge_graph.?.triples[0].label);
    try std.testing.expectEqualStrings("v0", decoded.knowledge_graph.?.source.?);

    try std.testing.expect(decoded.emotional_register != null);
    try std.testing.expectEqual(@as(usize, 1), decoded.emotional_register.?.axes.len);
    try std.testing.expectEqual(@as(f64, 0.82), decoded.emotional_register.?.axes[0].value);
    try std.testing.expectEqual(@as(i64, 1_700_000_321), decoded.emotional_register.?.observed_at.?);

    // Repeatable interaction-set: both elements preserved, in order.
    try std.testing.expectEqual(@as(usize, 2), decoded.interaction_sets.len);
    try std.testing.expectEqualSlices(u8, &([_]u8{0x33} ** 16), &decoded.interaction_sets[0].set_id);
    try std.testing.expectEqual(@as(usize, 1), decoded.interaction_sets[0].interactions.len);
    try std.testing.expectEqual(protocol.InteractionKind.act, decoded.interaction_sets[0].interactions[0].kind);
    try std.testing.expectEqualStrings("did a thing", decoded.interaction_sets[0].interactions[0].content.?);
    try std.testing.expectEqual(@as(i64, 1_700_000_500), decoded.interaction_sets[0].created.?);
    try std.testing.expectEqualSlices(u8, &([_]u8{0x44} ** 16), &decoded.interaction_sets[1].set_id);
    try std.testing.expectEqual(@as(usize, 0), decoded.interaction_sets[1].interactions.len);

    try std.testing.expect(decoded.policy != null);
    try std.testing.expectEqualStrings("secret", decoded.policy.?.admin_only[0]);
    try std.testing.expectEqualStrings("p", decoded.policy.?.note.?);
}

test "second-pass round-trip preserves attributes (grow path)" {
    // Models what `dreamball grow` does on a previously-grown envelope: read the
    // bytes back through the full decoder, mutate one field, re-encode. The
    // bug this guards against was the show/export/grow sites using the
    // subject-only decoder, which dropped name/feel/act on the floor before
    // they could be re-emitted.
    const gpa = std.testing.allocator;
    var arena1 = std.heap.ArenaAllocator.init(gpa);
    defer arena1.deinit();
    var arena2 = std.heap.ArenaAllocator.init(gpa);
    defer arena2.deinit();

    const feel = protocol.Feel{ .personality = "playful" };
    const act = protocol.Act{ .system_prompt = "payload-marker-abc" };
    const db1 = protocol.DreamBall{
        .stage = .dreamball,
        .dreamball_type = .tool,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 1,
        .name = "real-name",
        .feel = feel,
        .act = act,
    };

    const bytes1 = try encodeDreamBall(gpa, db1);
    defer gpa.free(bytes1);

    const db2 = try decodeDreamBall(arena1.allocator(), bytes1);
    try std.testing.expectEqualStrings("real-name", db2.name.?);
    try std.testing.expectEqualStrings("playful", db2.feel.?.personality.?);
    try std.testing.expectEqualStrings("payload-marker-abc", db2.act.?.system_prompt.?);

    // Second pass: re-encode from the decoded struct, decode again, assert
    // every field still present. Byte-equality of the two encodings is the
    // strongest possible round-trip guarantee.
    const bytes2 = try encodeDreamBall(gpa, db2);
    defer gpa.free(bytes2);
    try std.testing.expectEqualSlices(u8, bytes1, bytes2);

    const db3 = try decodeDreamBall(arena2.allocator(), bytes2);
    try std.testing.expectEqualStrings("real-name", db3.name.?);
    try std.testing.expectEqualStrings("playful", db3.feel.?.personality.?);
    try std.testing.expectEqualStrings("payload-marker-abc", db3.act.?.system_prompt.?);
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

// ============================================================================
// Story 2.3 — archiform_fp round-trip + implicit-binding back-compat (FR5).
// ============================================================================

const archiform_mod = @import("archiform.zig");

test "Story 2.3 AC1: archiform_fp round-trip — encoded envelope decodes byte-equal" {
    const gpa = std.testing.allocator;
    var arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();

    const fp_input: [32]u8 = archiform_mod.MEMORY_PALACE_IMPLICIT_FP;

    const db = protocol.DreamBall{
        .stage = .seed,
        .dreamball_type = .field,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 0,
        .field_kind = "palace",
        .archiform_fp = fp_input,
    };

    const bytes = try encodeDreamBall(gpa, db);
    defer gpa.free(bytes);

    const decoded = try decodeDreamBall(arena, bytes);
    try std.testing.expect(decoded.archiform_fp != null);
    try std.testing.expectEqualSlices(u8, &fp_input, &decoded.archiform_fp.?);
}

test "Story 2.3 AC2: implicit-binding back-compat — envelope without archiform_fp decodes" {
    // Sprint-001 envelopes lack archiform_fp on the wire. The decoder
    // returns null; consumers MUST substitute MEMORY_PALACE_IMPLICIT_FP
    // when binding. This test exercises both halves of that contract.
    const gpa = std.testing.allocator;
    var arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();

    const db_no_afp = protocol.DreamBall{
        .stage = .seed,
        .dreamball_type = .field,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 0,
        .field_kind = "palace",
        // archiform_fp omitted on purpose — sprint-001 wire shape.
    };

    const bytes = try encodeDreamBall(gpa, db_no_afp);
    defer gpa.free(bytes);

    // (a) Decode succeeds — IC1/IC4 forward-compat.
    const decoded = try decodeDreamBall(arena, bytes);
    // (b) The on-wire field is absent.
    try std.testing.expect(decoded.archiform_fp == null);

    // (c) Implicit-binding substitution per AC2: callers resolve to the
    //     Memory Palace fp baked at compile-time.
    const resolved: [32]u8 = decoded.archiform_fp orelse archiform_mod.MEMORY_PALACE_IMPLICIT_FP;
    try std.testing.expectEqualSlices(u8, &archiform_mod.MEMORY_PALACE_IMPLICIT_FP, &resolved);
}

test "Story 2.3 AC3: archiform_fp survives revision bump immutability" {
    // D-017: archiform_fp is immutable for the ball's lifetime. A
    // simulated revision bump (re-encode with same archiform_fp + bumped
    // revision) MUST preserve the genesis fp byte-for-byte.
    const gpa = std.testing.allocator;
    var arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();

    const fp_input: [32]u8 = archiform_mod.MEMORY_PALACE_IMPLICIT_FP;

    var db = protocol.DreamBall{
        .stage = .seed,
        .dreamball_type = .field,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 0,
        .field_kind = "palace",
        .archiform_fp = fp_input,
    };

    const genesis_bytes = try encodeDreamBall(gpa, db);
    defer gpa.free(genesis_bytes);
    const genesis_decoded = try decodeDreamBall(arena, genesis_bytes);

    // Simulate three subsequent revisions — the archiform_fp MUST NOT
    // mutate. (Drift would constitute the failure AC4 detects.)
    var revision: u32 = 1;
    while (revision <= 3) : (revision += 1) {
        db.revision = revision;
        const bytes = try encodeDreamBall(gpa, db);
        defer gpa.free(bytes);

        const dec = try decodeDreamBall(arena, bytes);
        try std.testing.expect(dec.archiform_fp != null);
        try std.testing.expectEqualSlices(u8, &genesis_decoded.archiform_fp.?, &dec.archiform_fp.?);
    }
}

test "Story 2.3 AC4: drift detection — mismatched archiform_fp values are distinguishable" {
    // A consistency-check helper sees two envelopes for the same ball
    // declaring different archiform_fp values; it MUST report drift.
    const gpa = std.testing.allocator;
    var arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();

    const fp_genesis: [32]u8 = archiform_mod.MEMORY_PALACE_IMPLICIT_FP;
    var fp_drift: [32]u8 = fp_genesis;
    fp_drift[0] ^= 0xFF;
    try std.testing.expect(!std.mem.eql(u8, &fp_genesis, &fp_drift));

    const db_a = protocol.DreamBall{
        .stage = .seed,
        .dreamball_type = .field,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 0,
        .field_kind = "palace",
        .archiform_fp = fp_genesis,
    };
    const db_b = protocol.DreamBall{
        .stage = .seed,
        .dreamball_type = .field,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 1,
        .field_kind = "palace",
        .archiform_fp = fp_drift,
    };

    const bytes_a = try encodeDreamBall(gpa, db_a);
    defer gpa.free(bytes_a);
    const bytes_b = try encodeDreamBall(gpa, db_b);
    defer gpa.free(bytes_b);

    const dec_a = try decodeDreamBall(arena, bytes_a);
    const dec_b = try decodeDreamBall(arena, bytes_b);

    try std.testing.expect(dec_a.archiform_fp != null);
    try std.testing.expect(dec_b.archiform_fp != null);
    try std.testing.expect(!std.mem.eql(u8, &dec_a.archiform_fp.?, &dec_b.archiform_fp.?));
}
