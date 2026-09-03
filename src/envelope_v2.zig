//! Protocol v2 envelope encoders. See docs/PROTOCOL.md §12.
//!
//! All encoders produce deterministic dCBOR output matching the v1
//! canonical-ordering rules. The one documented exception is the
//! omnispherical-grid envelope, which uses floats — see §12.2.
//!
//! CBOR primitives come from `zbor.builder` (https://codeberg.org/r4gus/zbor).
//! Map-key ordering is enforced manually at each callsite — the key lists here
//! are short and hand-sorted by (len asc, then lex). See comments on each
//! `writeMap` for the ordering rationale.

const std = @import("std");
const Allocator = std.mem.Allocator;

const zbor = @import("zbor");
const dcbor = @import("dcbor.zig");
const protocol = @import("protocol.zig");
const v2 = @import("protocol_v2.zig");
const envelope = @import("envelope.zig");
const Fingerprint = @import("fingerprint.zig").Fingerprint;

// ============================================================================
// ball.guild (§12.1.6) — a typed DreamBall envelope with a guild payload
// attached as auxiliary attributes.
// ============================================================================

pub fn encodeGuild(
    allocator: Allocator,
    identity: [32]u8,
    genesis_hash: [32]u8,
    guild: v2.Guild,
    signatures: []const protocol.Signature,
) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;

    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    // Count attributes up front (members + admins + policy + signatures + guild-name + keyspace-root-hash).
    var attribute_count: u64 = 2; // guild-name, keyspace-root-hash
    if (guild.policy != null) attribute_count += 1;
    for (guild.members) |_| attribute_count += 1;
    for (guild.members) |m| if (m.is_admin) {
        attribute_count += 1;
    };
    for (signatures) |_| attribute_count += 1;

    try zbor.builder.writeArray(w, 1 + attribute_count);

    // Core: tag 201 { type, format-version, identity, genesis-hash }
    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 4);
    // dCBOR canonical ordering: sort keys by (len, lex)
    // "type"(4) < "identity"(8) < "genesis-hash"(12) < "format-version"(14)
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.dreamball.guild");
    try zbor.builder.writeTextString(w, "identity");
    try zbor.builder.writeByteString(w, &identity);
    try zbor.builder.writeTextString(w, "genesis-hash");
    try zbor.builder.writeByteString(w, &genesis_hash);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    // Attributes as [label, value] 2-arrays. Emit in sorted label order.
    // For determinism we emit: admin, member, policy, signed, guild-name, keyspace-root-hash.
    // dCBOR ordering over those label lengths: "admin"(5), "member"(6), "policy"(6),
    // "signed"(6), "guild-name"(10), "keyspace-root-hash"(18).
    for (guild.members) |m| if (m.is_admin) {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "admin");
        try zbor.builder.writeByteString(w, &m.member.bytes);
    };

    // members (all — admins are also listed under "member")
    for (guild.members) |m| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "member");
        try zbor.builder.writeByteString(w, &m.member.bytes);
    }

    if (guild.policy) |p| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "policy");
        try writePolicy(w, p);
    }

    for (signatures) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "signed");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, s.alg);
        try zbor.builder.writeByteString(w, s.value);
    }

    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "guild-name");
    try zbor.builder.writeTextString(w, guild.guild_name);

    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "keyspace-root-hash");
    try zbor.builder.writeByteString(w, &guild.keyspace_root_hash);

    return ai.toOwnedSlice();
}

fn writePolicy(w: *std.Io.Writer, p: v2.GuildPolicy) !void {
    // Emit a simple map { "public": [...], "guild-only": [...], "admin-only": [...] }.
    // Keys sorted canonically: "public"(6), "admin-only"(10), "guild-only"(10).
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 5); // type, format-version, public, admin-only, guild-only
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.guild-policy");
    try zbor.builder.writeTextString(w, "public");
    try zbor.builder.writeArray(w, p.public.len);
    for (p.public) |s| try zbor.builder.writeTextString(w, s);
    try zbor.builder.writeTextString(w, "admin-only");
    try zbor.builder.writeArray(w, p.admin_only.len);
    for (p.admin_only) |s| try zbor.builder.writeTextString(w, s);
    try zbor.builder.writeTextString(w, "guild-only");
    try zbor.builder.writeArray(w, p.guild_only.len);
    for (p.guild_only) |s| try zbor.builder.writeTextString(w, s);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));
}

// ============================================================================
// ball.dreamball.relic (§12.1.4) — a typed DreamBall that wraps a sealed
// inner node. Core carries `sealed-payload-hash` + `unlock-guild`.
// ============================================================================

pub fn encodeRelic(
    allocator: Allocator,
    identity: [32]u8,
    identity_pq: ?[protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8,
    genesis_hash: [32]u8,
    relic: v2.Relic,
    reveal_hint: ?[]const u8,
    signatures: []const protocol.Signature,
) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;

    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var attribute_count: u64 = 0;
    if (reveal_hint != null) attribute_count += 1;
    if (relic.sealed_until != null) attribute_count += 1;
    for (signatures) |_| attribute_count += 1;

    try zbor.builder.writeArray(w, 1 + attribute_count);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys canonically sorted (len asc, lex within equal len):
    //   "type"(4), "identity"(8), "identity-pq"(11), "genesis-hash"(12),
    //   "unlock-guild"(12), "format-version"(14), "sealed-payload-hash"(19).
    // identity-pq is optional; when set, format-version bumps to V3.
    const core_len: u64 = if (identity_pq != null) 7 else 6;
    const fv: u32 = if (identity_pq != null)
        protocol.FORMAT_VERSION_V3
    else
        protocol.FORMAT_VERSION_V2;
    try zbor.builder.writeMap(w, core_len);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.dreamball.relic");
    try zbor.builder.writeTextString(w, "identity");
    try zbor.builder.writeByteString(w, &identity);
    if (identity_pq) |pq| {
        try zbor.builder.writeTextString(w, "identity-pq");
        try zbor.builder.writeByteString(w, &pq);
    }
    // "genesis-hash" < "unlock-guild" lex (g < u) so genesis first at len 12.
    try zbor.builder.writeTextString(w, "genesis-hash");
    try zbor.builder.writeByteString(w, &genesis_hash);
    try zbor.builder.writeTextString(w, "unlock-guild");
    try zbor.builder.writeByteString(w, &relic.unlock_guild.bytes);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(fv));
    try zbor.builder.writeTextString(w, "sealed-payload-hash");
    try zbor.builder.writeByteString(w, &relic.sealed_payload_hash);

    if (reveal_hint) |hint| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "reveal-hint");
        try zbor.builder.writeTextString(w, hint);
    }
    if (relic.sealed_until) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "sealed-until");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
    for (signatures) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "signed");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, s.alg);
        try zbor.builder.writeByteString(w, s.value);
    }

    return ai.toOwnedSlice();
}

// ============================================================================
// ball.transmission (§12.9) — receipt of a Tool transfer.
// ============================================================================

pub fn encodeTransmission(
    allocator: Allocator,
    t: v2.Transmission,
) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;

    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var attribute_count: u64 = 1; // tool-envelope
    if (t.sender_fp != null) attribute_count += 1;
    if (t.transmitted_at != null) attribute_count += 1;
    for (t.signatures) |_| attribute_count += 1;

    try zbor.builder.writeArray(w, 1 + attribute_count);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys canonical (len asc, lex): "type"(4), "tool-fp"(7),
    //   "target-fp"(9), "via-guild"(9), "format-version"(14),
    //   "sender-identity"(15), "sender-identity-pq"(18).
    // sender-identity makes the receipt self-verifying. When present,
    // format-version bumps to V3. sender-identity-pq requires
    // sender-identity to be set.
    var core_len: u64 = 5;
    if (t.sender_identity != null) core_len += 1;
    if (t.sender_identity_pq != null) core_len += 1;
    const fv: u32 = if (t.sender_identity != null)
        protocol.FORMAT_VERSION_V3
    else
        protocol.FORMAT_VERSION_V2;
    try zbor.builder.writeMap(w, core_len);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.transmission");
    try zbor.builder.writeTextString(w, "tool-fp");
    try zbor.builder.writeByteString(w, &t.tool_fp.bytes);
    try zbor.builder.writeTextString(w, "target-fp");
    try zbor.builder.writeByteString(w, &t.target_fp.bytes);
    try zbor.builder.writeTextString(w, "via-guild");
    try zbor.builder.writeByteString(w, &t.via_guild.bytes);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(fv));
    if (t.sender_identity) |si| {
        try zbor.builder.writeTextString(w, "sender-identity");
        try zbor.builder.writeByteString(w, &si);
    }
    if (t.sender_identity_pq) |spq| {
        try zbor.builder.writeTextString(w, "sender-identity-pq");
        try zbor.builder.writeByteString(w, &spq);
    }

    // Attributes in sorted order: "sender-fp"(9), "signed"(6), "tool-envelope"(13), "transmitted-at"(14).
    // len-first ordering: "signed"(6) < "sender-fp"(9) < "tool-envelope"(13) < "transmitted-at"(14).
    for (t.signatures) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "signed");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, s.alg);
        try zbor.builder.writeByteString(w, s.value);
    }
    if (t.sender_fp) |fp| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "sender-fp");
        try zbor.builder.writeByteString(w, &fp.bytes);
    }
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "tool-envelope");
    // Inline the tool envelope bytes verbatim (already dCBOR).
    try w.writeAll(t.tool_envelope);
    if (t.transmitted_at) |ts| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "transmitted-at");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(ts));
    }

    return ai.toOwnedSlice();
}

// ============================================================================
// The knowledge-graph / emotional-register / interaction-set / guild-policy
// slot codecs were promoted to envelope.zig as first-class DreamBall slots
// (beside encodeMemory/decodeMemory) — see §12.3-12.7 and
// docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md. The memory
// slot moved earlier in the same refactor.
// ============================================================================

// ============================================================================
// §13.2 ball.layout — encoder + decoder
// ============================================================================

pub fn encodeLayout(allocator: Allocator, l: v2.Layout) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    const ac: u64 = l.placements.len + @as(u64, if (l.note != null) 1 else 0);
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // dCBOR canonical order (len asc, lex): "type"(4), "format-version"(14)
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Layout.type_string);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Layout.format_version));

    for (l.placements) |p| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "placement");
        // { "child-fp": h'…', "position": [x,y,z], "facing": [qx,qy,qz,qw] }
        // Keys sorted: "facing"(6) < "position"(8) < "child-fp"(8) — "child-fp" vs "position"
        // len: "facing"=6, "position"=8, "child-fp"=8 — at len 8: "child-fp" < "position" lex
        try zbor.builder.writeMap(w, 3);
        try zbor.builder.writeTextString(w, "facing");
        try zbor.builder.writeArray(w, 4);
        try dcbor.writeSmallestFloat(w, p.facing.qx);
        try dcbor.writeSmallestFloat(w, p.facing.qy);
        try dcbor.writeSmallestFloat(w, p.facing.qz);
        try dcbor.writeSmallestFloat(w, p.facing.qw);
        try zbor.builder.writeTextString(w, "child-fp");
        try zbor.builder.writeByteString(w, &p.child_fp);
        try zbor.builder.writeTextString(w, "position");
        try zbor.builder.writeArray(w, 3);
        try dcbor.writeSmallestFloat(w, p.position[0]);
        try dcbor.writeSmallestFloat(w, p.position[1]);
        try dcbor.writeSmallestFloat(w, p.position[2]);
    }
    if (l.note) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "note");
        try zbor.builder.writeTextString(w, n);
    }
    return ai.toOwnedSlice();
}

// Dreamball-h7s.1 removed §13.10 `ball.object3d`'s `encodeObject3d` along
// with the `v2.Object3d` type it encoded (demo of the dissolved Zig-canonical
// authoring pipeline). The golden fixture bytes are preserved as pinned data
// in src/golden.zig (`GOLDEN_OBJECT3D_BYTES_HEX` / `GOLDEN_OBJECT3D_BLAKE3`);
// `tools/export-golden-fixtures/main.zig` now emits the manifest entry by
// decoding those bytes directly instead of re-deriving them here.

// These shared envelope decode helpers were relocated DOWN to dcbor.zig to
// break the protocol/envelope ↔ v2 import cycle (so envelope.zig can decode
// the memory slot too). The aliases below keep this module's ~50 existing
// call sites unchanged. See dcbor.zig "Envelope decode helpers".
const DecodeError = dcbor.DecodeError;
const mapDecodeError = dcbor.mapDecodeError;
const assertCanonical = dcbor.assertCanonical;
const assertCanonicalAllowFloats = dcbor.assertCanonicalAllowFloats;
const readEnvelopeHeader = dcbor.readEnvelopeHeader;
const skipCoreMap = dcbor.skipCoreMap;
const readCoreFields = dcbor.readCoreFields;

pub fn decodeLayout(allocator: Allocator, bytes: []const u8) !struct {
    layout: v2.Layout,
    placements: []v2.Placement,
    note_buf: ?[]u8,
} {
    try assertCanonicalAllowFloats(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);
    _ = try readCoreFields(bytes, &cursor); // skip core map fields
    // We already counted core fields so skip them
    // Actually readCoreFields returned the map pair count; we need to skip those pairs.
    // Restart: use skipCoreMap instead.
    cursor = 0;
    _ = try readEnvelopeHeader(bytes, &cursor);
    try skipCoreMap(bytes, &cursor);

    var placements: []v2.Placement = &.{};
    var placement_list: std.ArrayListUnmanaged(v2.Placement) = .empty;
    defer placement_list.deinit(allocator);
    var note_buf: ?[]u8 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "placement")) {
            const map_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
            var child_fp: ?[32]u8 = null;
            var position: ?[3]f32 = null;
            var facing: ?v2.Quaternion = null;
            var mi: u64 = 0;
            while (mi < map_n) : (mi += 1) {
                const mk = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
                if (std.mem.eql(u8, mk, "child-fp")) {
                    const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
                    if (b.len != 32) return DecodeError.InvalidValue;
                    var fp: [32]u8 = undefined;
                    @memcpy(&fp, b);
                    child_fp = fp;
                } else if (std.mem.eql(u8, mk, "position")) {
                    const arr3 = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
                    if (arr3 != 3) return DecodeError.InvalidValue;
                    const x = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
                    const y = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
                    const z = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
                    position = .{ x, y, z };
                } else if (std.mem.eql(u8, mk, "facing")) {
                    const arr4 = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
                    if (arr4 != 4) return DecodeError.InvalidValue;
                    const qx = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
                    const qy = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
                    const qz = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
                    const qw = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
                    facing = .{ .qx = qx, .qy = qy, .qz = qz, .qw = qw };
                } else {
                    dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
                }
            }
            try placement_list.append(allocator, .{
                .child_fp = child_fp orelse return DecodeError.MissingField,
                .position = position orelse return DecodeError.MissingField,
                .facing = facing orelse return DecodeError.MissingField,
            });
        } else if (std.mem.eql(u8, key, "note")) {
            const t = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
            note_buf = try allocator.dupe(u8, t);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    placements = try placement_list.toOwnedSlice(allocator);
    return .{
        .layout = .{ .placements = placements, .note = if (note_buf) |nb| nb else null },
        .placements = placements,
        .note_buf = note_buf,
    };
}

// ============================================================================
// §13.3 ball.timeline — encoder + decoder
// ============================================================================

pub fn encodeTimeline(allocator: Allocator, t: v2.Timeline) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    const ac: u64 = t.head_hashes.len + @as(u64, if (t.note != null) 1 else 0);
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted (len asc, lex): "type"(4), "palace-fp"(9), "format-version"(14)
    try zbor.builder.writeMap(w, 3);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Timeline.type_string);
    try zbor.builder.writeTextString(w, "palace-fp");
    try zbor.builder.writeByteString(w, &t.palace_fp);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Timeline.format_version));

    for (t.head_hashes) |hh| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "head-hashes");
        try zbor.builder.writeByteString(w, &hh);
    }
    if (t.note) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "note");
        try zbor.builder.writeTextString(w, n);
    }
    return ai.toOwnedSlice();
}

pub fn decodeTimeline(allocator: Allocator, bytes: []const u8) !struct {
    timeline: v2.Timeline,
    palace_fp: [32]u8,
    head_hashes: [][32]u8,
    note_buf: ?[]u8,
} {
    try assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);

    // Read core
    dcbor.expectTag(bytes, &cursor, dcbor.Tag.leaf) catch |e| return mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
    var palace_fp: ?[32]u8 = null;
    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, k, "palace-fp")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, b);
            palace_fp = fp;
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    var head_list = std.ArrayListUnmanaged([32]u8).empty;
    defer head_list.deinit(allocator);
    var note_buf: ?[]u8 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "head-hashes")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var hh: [32]u8 = undefined;
            @memcpy(&hh, b);
            try head_list.append(allocator, hh);
        } else if (std.mem.eql(u8, key, "note")) {
            const tx = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
            note_buf = try allocator.dupe(u8, tx);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    const pfp = palace_fp orelse return DecodeError.MissingField;
    const hh_slice = try head_list.toOwnedSlice(allocator);
    return .{
        .timeline = .{
            .palace_fp = pfp,
            .head_hashes = hh_slice,
            .note = if (note_buf) |nb| nb else null,
        },
        .palace_fp = pfp,
        .head_hashes = hh_slice,
        .note_buf = note_buf,
    };
}

// ============================================================================
// §13.3 ball.action — encoder + decoder
// ============================================================================

// The v3 `encodeAction` (closed palace profile — 5-key core map,
// `"action-kind"`, `format-version` pinned to the literal 3) was deleted here
// (Dreamball-y4t.15, 2026-08-07): the core substrate now supports ONLY v4
// `ball.action`. See docs/PROTOCOL.md §16.7 for the rationale (no consumers,
// no data, Memory Palace — the v3 profile's only owner — is being extracted
// to its own repo, Dreamball-etk). The palace CLI verbs that still author v3
// envelopes keep a verbatim copy of this function in
// `src/cli/internal/palace_action_v3.zig` (`encodeActionV3`) until that
// extraction lands.

/// v4 `ball.action` encoder — the OPEN type-system wire shape (D-037/D-038/
/// D-039/D-043; frozen in PROTOCOL.md §16.7/§17/§18). v3 support (the closed
/// palace profile) has been removed from this file (Dreamball-y4t.15); v4 is
/// now the only format `encodeAction`'s sibling `decodeAction` accepts. B1's
/// `authorAction` WASM export links THIS function.
///
/// Core-map keys in dCBOR length-first order (lex within equal length):
///   "hlc"(3) · "body"(4) · "kind"(4) · "type"(4) · "actor"(5)
///   · "parent-hashes"(13) · "format-version"(14)
/// Among the length-4 keys: "body" < "kind" < "type". When `body` is absent it
/// is simply omitted and the core map is 6 keys (PROTOCOL.md §16.7).
///
/// `body` is embedded as a CBOR byte string (major type 2) wrapping the
/// consumer's canonical CBOR — CBOR-in-CBOR, opaque to the protocol (D-043).
/// `verifyCanonical` does NOT recurse into a byte string, so we `assertCanonical`
/// the body bytes up front: that is the only point the body's own canonicality
/// is enforced, and it keeps a non-canonical payload off the wire (A3 owns the
/// richer decode-side rejection path). `hlc` is a bare 2-element array of dCBOR
/// shortest-form unsigned ints `[l, c]` — no CBOR tag (D-039).
pub fn encodeActionV4(allocator: Allocator, a: v2.Action) ![]u8 {
    return encodeActionV4Signed(allocator, a, &.{});
}

/// `content_hash` for a v4 `ball.action` — the op's portable identity.
/// `content_hash = Blake3-256(canonical UNSIGNED envelope bytes)` with NO
/// domain-separation prefix (D-043, PROTOCOL.md §16.7/§17.4). The unsigned
/// bytes are the encodeActionV4 output (zero `signed` attributes); a verifier
/// strips any signatures and recomputes over these same bytes. Cross-runtime
/// invariant: every runtime that hashes the same logical action MUST get this
/// exact digest (golden vector in `src/golden.zig`, gated CLI≡WASM in C1).
pub fn contentHash(allocator: Allocator, a: v2.Action) ![32]u8 {
    const bytes = try encodeActionV4(allocator, a);
    defer allocator.free(bytes);
    var out: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &out, .{});
    return out;
}

/// v4 `ball.action` encoder that ALSO appends one `signed` attribute per
/// signature — the signed-envelope form B1's `authorAction` WASM export returns
/// (D-042). `encodeActionV4` above is the zero-signature special case and stays
/// the canonical *unsigned* shape that A2's round-trip tests and C1's
/// `content_hash` domain pin (the `signed` attributes are NOT part of the bytes
/// a producer signs — a verifier strips them, exactly as for DreamBall envelopes,
/// PROTOCOL.md §16.7 / §2.3).
///
/// Attribute order is the v3/v4 canonical run with `signed`(6) slotted between
/// `nacks`(5) and `target-fp`(9): "deps"(4) · "nacks"(5) · "signed"(6) ·
/// "target-fp"(9) · "timestamp"(9). Each `signed` attribute is the same
/// `[label, [alg, value]]` 2-array used by every other v2 envelope encoder
/// (see `encodeGuild`).
pub fn encodeActionV4Signed(
    allocator: Allocator,
    a: v2.Action,
    signatures: []const protocol.Signature,
) ![]u8 {
    // Reject a non-canonical body before allocating any output — the body is
    // opaque once embedded, so this is the encoder's only window to check it.
    if (a.body) |b| try assertCanonical(b);

    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    // parent_hashes lives in the core map; the attribute set mirrors v3 exactly
    // (deps, nacks, target-fp, timestamp) per AC3, plus any `signed` attributes.
    var ac: u64 = a.deps.len + a.nacks.len + signatures.len;
    if (a.target_fp != null) ac += 1;
    if (a.timestamp != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // 7 keys when a body is present, 6 when absent.
    const core_len: u64 = if (a.body != null) 7 else 6;
    try zbor.builder.writeMap(w, core_len);
    // "hlc"(3) — bare [l, c] array, no tag.
    try zbor.builder.writeTextString(w, "hlc");
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeInt(w, @intCast(a.hlc[0]));
    try zbor.builder.writeInt(w, @intCast(a.hlc[1]));
    // "body"(4) — optional; first of the length-4 keys (b < k < t).
    if (a.body) |b| {
        try zbor.builder.writeTextString(w, "body");
        try zbor.builder.writeByteString(w, b);
    }
    // "kind"(4) — open UTF-8 string.
    try zbor.builder.writeTextString(w, "kind");
    try zbor.builder.writeTextString(w, a.kind);
    // "type"(4)
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Action.type_string);
    // "actor"(5)
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &a.actor);
    // "parent-hashes"(13)
    try zbor.builder.writeTextString(w, "parent-hashes");
    try zbor.builder.writeArray(w, a.parent_hashes.len);
    for (a.parent_hashes) |ph| try zbor.builder.writeByteString(w, &ph);
    // "format-version"(14)
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Action.format_version));

    // Attributes, sorted exactly as v3: "deps"(4), "nacks"(5),
    // "target-fp"(9) < "timestamp"(9).
    for (a.deps) |d| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "deps");
        try zbor.builder.writeByteString(w, &d);
    }
    for (a.nacks) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "nacks");
        try zbor.builder.writeByteString(w, &n);
    }
    // "signed"(6) — slots between nacks(5) and target-fp(9). Same shape as
    // every other v2 envelope: [label, [alg, value]].
    for (signatures) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "signed");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, s.alg);
        try zbor.builder.writeByteString(w, s.value);
    }
    if (a.target_fp) |tfp| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "target-fp");
        try zbor.builder.writeByteString(w, &tfp);
    }
    if (a.timestamp) |ts| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "timestamp");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(ts));
    }
    return ai.toOwnedSlice();
}

pub fn decodeAction(allocator: Allocator, bytes: []const u8) !struct {
    action: v2.Action,
    parent_hashes: [][32]u8,
    deps: []v2.ActionRef,
    nacks: []v2.ActionRef,
} {
    try assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);

    // Read the core map generically, then branch on `format-version` (D-037).
    // The version is the discriminant but it is the LAST core key in dCBOR
    // length-first order (longest key), so we collect every field first and
    // decide on the format once the whole core map has been read.
    //
    // Decoders MUST still branch on `format-version` before interpreting the
    // rest of the core map (PROTOCOL.md §16.7) — this loop reads every field
    // generically first for exactly that reason. `format-version: 3` (the
    // closed v3 palace profile) is a recognized-but-REJECTED value, not an
    // unknown one: Dreamball-y4t.15 dropped v3 `ball.action` from the core
    // substrate, so a v3 envelope now fails cleanly with
    // `DecodeError.UnsupportedFormatVersion` rather than silently misparsing.
    // A legacy `"action-kind"` key (the v3 closed-palette field) falls
    // through to the generic skip below — its value no longer needs to be
    // captured since v3 is rejected outright regardless of its content.
    dcbor.expectTag(bytes, &cursor, dcbor.Tag.leaf) catch |e| return mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
    var open_kind_opt: ?[]const u8 = null; // v4 "kind" (open string)
    var actor_opt: ?[32]u8 = null;
    var format_version: ?u64 = null;
    var hlc: [2]u64 = .{ 0, 0 };
    var hlc_present = false;
    var body_opt: ?[]const u8 = null;
    var parent_list = std.ArrayListUnmanaged([32]u8).empty;
    defer parent_list.deinit(allocator);

    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, k, "kind")) {
            open_kind_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, k, "actor")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, b);
            actor_opt = fp;
        } else if (std.mem.eql(u8, k, "parent-hashes")) {
            const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
            var pi: u64 = 0;
            while (pi < arr_n) : (pi += 1) {
                const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
                if (b.len != 32) return DecodeError.InvalidValue;
                var ph: [32]u8 = undefined;
                @memcpy(&ph, b);
                try parent_list.append(allocator, ph);
            }
        } else if (std.mem.eql(u8, k, "hlc")) {
            // [l, c] — bare 2-element array of dCBOR uints (D-039).
            const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (arr_n != 2) return DecodeError.InvalidValue;
            hlc[0] = dcbor.readUint(bytes, &cursor) catch |e| return mapDecodeError(e);
            hlc[1] = dcbor.readUint(bytes, &cursor) catch |e| return mapDecodeError(e);
            hlc_present = true;
        } else if (std.mem.eql(u8, k, "body")) {
            // Opaque CBOR-in-CBOR; returned to the caller as raw bytes (D-043).
            body_opt = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, k, "format-version")) {
            format_version = dcbor.readUint(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    var deps_list = std.ArrayListUnmanaged(v2.ActionRef).empty;
    defer deps_list.deinit(allocator);
    var nacks_list = std.ArrayListUnmanaged(v2.ActionRef).empty;
    defer nacks_list.deinit(allocator);
    var target_fp: ?[32]u8 = null;
    var timestamp: ?i64 = null;

    var aii: u64 = 0;
    while (aii < attr_count) : (aii += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "deps")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var ref: [32]u8 = undefined;
            @memcpy(&ref, b);
            try deps_list.append(allocator, ref);
        } else if (std.mem.eql(u8, key, "nacks")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var ref: [32]u8 = undefined;
            @memcpy(&ref, b);
            try nacks_list.append(allocator, ref);
        } else if (std.mem.eql(u8, key, "target-fp")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, b);
            target_fp = fp;
        } else if (std.mem.eql(u8, key, "timestamp")) {
            dcbor.expectTag(bytes, &cursor, dcbor.Tag.epoch_time) catch |e| return mapDecodeError(e);
            const ts = dcbor.readUint(bytes, &cursor) catch |e| return mapDecodeError(e);
            timestamp = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    // Resolve the version-specific fields BEFORE taking ownership of the lists,
    // so an early error return cannot leak the to-be-owned slices.
    const fv = format_version orelse return DecodeError.MissingField;
    var decoded_kind: []const u8 = undefined;
    var decoded_body: ?[]const u8 = null;
    var decoded_hlc: [2]u64 = .{ 0, 0 };
    if (fv == v2.Action.format_version) {
        // v4 — open kind, mandatory HLC (§17), optional opaque body.
        decoded_kind = open_kind_opt orelse return DecodeError.MissingField;
        // §18.1 — zero-length kind is a decode error.
        if (decoded_kind.len == 0) return DecodeError.InvalidValue;
        if (!hlc_present) return DecodeError.MissingField;
        decoded_hlc = hlc;
        decoded_body = body_opt;
        // D-041/D-043 — body well-formedness gate (defense in depth). The outer
        // assertCanonical at entry walks past the body byte-string without
        // inspecting its contents, so the inner bytes are checked here.
        if (decoded_body) |b| try assertCanonical(b);
    } else if (fv == 3) {
        // v3 palace profile — CLOSED, dropped from the core substrate
        // (Dreamball-y4t.15, 2026-08-07). Reject cleanly rather than
        // attempting to interpret the rest of the core map: no consumers, no
        // data to migrate, and the profile belongs with the Memory Palace
        // extraction (Dreamball-etk), not here. See docs/PROTOCOL.md §16.7.
        return DecodeError.UnsupportedFormatVersion;
    } else {
        return DecodeError.InvalidValue; // unknown format-version
    }
    const actor = actor_opt orelse return DecodeError.MissingField;

    const ph_slice = try parent_list.toOwnedSlice(allocator);
    const deps_slice = try deps_list.toOwnedSlice(allocator);
    const nacks_slice = try nacks_list.toOwnedSlice(allocator);
    return .{
        .action = .{
            .kind = decoded_kind,
            .actor = actor,
            .parent_hashes = ph_slice,
            .body = decoded_body,
            .hlc = decoded_hlc,
            .deps = deps_slice,
            .nacks = nacks_slice,
            .target_fp = target_fp,
            .timestamp = timestamp,
        },
        .parent_hashes = ph_slice,
        .deps = deps_slice,
        .nacks = nacks_slice,
    };
}

// ============================================================================
// §13.4 ball.aqueduct — encoder + decoder
// ============================================================================

pub fn encodeAqueduct(allocator: Allocator, aq: v2.Aqueduct) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    // Attributes: capacity, strength, resistance, capacitance always present;
    // conductance optional; phase optional; last-traversed optional.
    var ac: u64 = 4; // capacity, strength, resistance, capacitance
    if (aq.conductance != null) ac += 1;
    if (aq.phase != null) ac += 1;
    if (aq.last_traversed != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted (len asc, lex): "to"(2), "from"(4), "kind"(4), "type"(4), "format-version"(14)
    // At len 4: "from" < "kind" < "type" lex
    try zbor.builder.writeMap(w, 5);
    try zbor.builder.writeTextString(w, "to");
    try zbor.builder.writeByteString(w, &aq.to);
    try zbor.builder.writeTextString(w, "from");
    try zbor.builder.writeByteString(w, &aq.from);
    try zbor.builder.writeTextString(w, "kind");
    try zbor.builder.writeTextString(w, aq.kind);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Aqueduct.type_string);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Aqueduct.format_version));

    // Attributes sorted by label (len asc, lex):
    // "phase"(5) < "strength"(8) < "capacity"(8) — "capacity" < "strength" lex
    // "resistance"(10) < "capacitance"(11) < "conductance"(11) — "capacitance" < "conductance" lex
    // "last-traversed"(14)
    if (aq.phase) |ph| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "phase");
        try zbor.builder.writeTextString(w, ph.toWireString());
    }
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "capacity");
    try dcbor.writeSmallestFloat(w, aq.capacity);
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "strength");
    try dcbor.writeSmallestFloat(w, aq.strength);
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "resistance");
    try dcbor.writeSmallestFloat(w, aq.resistance);
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "capacitance");
    try dcbor.writeSmallestFloat(w, aq.capacitance);
    if (aq.conductance) |c| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "conductance");
        try dcbor.writeSmallestFloat(w, c);
    }
    if (aq.last_traversed) |lt| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "last-traversed");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(lt));
    }
    return ai.toOwnedSlice();
}

pub fn decodeAqueduct(allocator: Allocator, bytes: []const u8) !v2.Aqueduct {
    _ = allocator;
    try assertCanonicalAllowFloats(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);

    dcbor.expectTag(bytes, &cursor, dcbor.Tag.leaf) catch |e| return mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
    var from_opt: ?[32]u8 = null;
    var to_opt: ?[32]u8 = null;
    var kind_opt: ?[]const u8 = null;

    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, k, "from")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, b);
            from_opt = fp;
        } else if (std.mem.eql(u8, k, "to")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, b);
            to_opt = fp;
        } else if (std.mem.eql(u8, k, "kind")) {
            kind_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    var capacity: f32 = 0;
    var strength: f32 = 0;
    var resistance: f32 = 0;
    var capacitance: f32 = 0;
    var conductance: ?f32 = null;
    var phase: ?v2.AqueductPhase = null;
    var last_traversed: ?i64 = null;

    var aii: u64 = 0;
    while (aii < attr_count) : (aii += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "capacity")) {
            capacity = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "strength")) {
            strength = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "resistance")) {
            resistance = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "capacitance")) {
            capacitance = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "conductance")) {
            conductance = dcbor.readAnyFloatF32(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "phase")) {
            const ps = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (std.mem.eql(u8, ps, "in")) {
                phase = .in;
            } else if (std.mem.eql(u8, ps, "out")) {
                phase = .out;
            } else if (std.mem.eql(u8, ps, "standing")) {
                phase = .standing;
            } else if (std.mem.eql(u8, ps, "resonant")) {
                phase = .resonant;
            } else return DecodeError.InvalidValue;
        } else if (std.mem.eql(u8, key, "last-traversed")) {
            dcbor.expectTag(bytes, &cursor, dcbor.Tag.epoch_time) catch |e| return mapDecodeError(e);
            const ts = dcbor.readUint(bytes, &cursor) catch |e| return mapDecodeError(e);
            last_traversed = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    return .{
        .from = from_opt orelse return DecodeError.MissingField,
        .to = to_opt orelse return DecodeError.MissingField,
        .kind = kind_opt orelse return DecodeError.MissingField,
        .capacity = capacity,
        .strength = strength,
        .resistance = resistance,
        .capacitance = capacitance,
        .conductance = conductance,
        .phase = phase,
        .last_traversed = last_traversed,
    };
}

// ============================================================================
// §13.5 ball.element-tag — encoder + decoder
// ============================================================================

pub fn encodeElementTag(allocator: Allocator, et: v2.ElementTag) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = 1; // element always present
    if (et.phase != null) ac += 1;
    if (et.note != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted (len asc, lex): "type"(4), "format-version"(14)
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.ElementTag.type_string);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.ElementTag.format_version));

    // Attributes sorted: "note"(4), "phase"(5), "element"(7)
    if (et.note) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "note");
        try zbor.builder.writeTextString(w, n);
    }
    if (et.phase) |ph| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "phase");
        try zbor.builder.writeTextString(w, ph);
    }
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "element");
    try zbor.builder.writeTextString(w, et.element);
    return ai.toOwnedSlice();
}

pub fn decodeElementTag(bytes: []const u8) !v2.ElementTag {
    try assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);
    try skipCoreMap(bytes, &cursor);

    var element_opt: ?[]const u8 = null;
    var phase_opt: ?[]const u8 = null;
    var note_opt: ?[]const u8 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "element")) {
            element_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "phase")) {
            phase_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "note")) {
            note_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }
    return .{
        .element = element_opt orelse return DecodeError.MissingField,
        .phase = phase_opt,
        .note = note_opt,
    };
}

// ============================================================================
// §13.6 ball.trust-observation — encoder + decoder
// ============================================================================

pub fn encodeTrustObservation(allocator: Allocator, to: v2.TrustObservation) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = to.axes.len + to.signatures.len;
    if (to.observed_at != null) ac += 1;
    if (to.context != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted (len asc, lex): "type"(4), "about"(5), "observer"(8), "format-version"(14)
    try zbor.builder.writeMap(w, 4);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.TrustObservation.type_string);
    try zbor.builder.writeTextString(w, "about");
    try zbor.builder.writeByteString(w, &to.about);
    try zbor.builder.writeTextString(w, "observer");
    try zbor.builder.writeByteString(w, &to.observer);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.TrustObservation.format_version));

    // Attributes sorted: "axis"(4), "context"(7), "observer-at" → "observed-at"(11), "signed"(6)
    // len: "axis"(4), "signed"(6), "context"(7), "observed-at"(11)
    for (to.axes) |ax| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "axis");
        // { "name": …, "value": …, "range": [lo, hi] }
        // Keys sorted: "name"(4), "range"(5), "value"(5) — "range" < "value" lex
        try zbor.builder.writeMap(w, 3);
        try zbor.builder.writeTextString(w, "name");
        try zbor.builder.writeTextString(w, ax.name);
        try zbor.builder.writeTextString(w, "range");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeFloat(w, ax.range[0]);
        try zbor.builder.writeFloat(w, ax.range[1]);
        try zbor.builder.writeTextString(w, "value");
        try zbor.builder.writeFloat(w, ax.value);
    }
    for (to.signatures) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "signed");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, s.alg);
        try zbor.builder.writeByteString(w, s.value);
    }
    if (to.context) |ctx| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "context");
        try zbor.builder.writeTextString(w, ctx);
    }
    if (to.observed_at) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "observed-at");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
    return ai.toOwnedSlice();
}

pub fn decodeTrustObservation(allocator: Allocator, bytes: []const u8) !struct {
    obs: v2.TrustObservation,
    axes: []v2.TrustAxis,
    observer: [32]u8,
    about: [32]u8,
} {
    try assertCanonicalAllowFloats(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);

    dcbor.expectTag(bytes, &cursor, dcbor.Tag.leaf) catch |e| return mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
    var observer_opt: ?[32]u8 = null;
    var about_opt: ?[32]u8 = null;
    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, k, "observer")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, b);
            observer_opt = fp;
        } else if (std.mem.eql(u8, k, "about")) {
            const b = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (b.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, b);
            about_opt = fp;
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    var axes_list = std.ArrayListUnmanaged(v2.TrustAxis).empty;
    defer axes_list.deinit(allocator);
    var context_opt: ?[]const u8 = null;
    var observed_at: ?i64 = null;

    var aii: u64 = 0;
    while (aii < attr_count) : (aii += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "axis")) {
            const map_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
            var name_opt: ?[]const u8 = null;
            var value: f64 = 0;
            var range: [2]f64 = .{ 0.0, 1.0 };
            var mi: u64 = 0;
            while (mi < map_n) : (mi += 1) {
                const mk = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
                if (std.mem.eql(u8, mk, "name")) {
                    name_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
                } else if (std.mem.eql(u8, mk, "value")) {
                    value = dcbor.readAnyFloat(bytes, &cursor) catch |e| return mapDecodeError(e);
                } else if (std.mem.eql(u8, mk, "range")) {
                    const arr2 = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
                    if (arr2 != 2) return DecodeError.InvalidValue;
                    range[0] = dcbor.readAnyFloat(bytes, &cursor) catch |e| return mapDecodeError(e);
                    range[1] = dcbor.readAnyFloat(bytes, &cursor) catch |e| return mapDecodeError(e);
                } else {
                    dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
                }
            }
            try axes_list.append(allocator, .{
                .name = name_opt orelse return DecodeError.MissingField,
                .value = value,
                .range = range,
            });
        } else if (std.mem.eql(u8, key, "context")) {
            context_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "observed-at")) {
            dcbor.expectTag(bytes, &cursor, dcbor.Tag.epoch_time) catch |e| return mapDecodeError(e);
            const ts = dcbor.readUint(bytes, &cursor) catch |e| return mapDecodeError(e);
            observed_at = @intCast(ts);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    const axes_slice = try axes_list.toOwnedSlice(allocator);
    const obs = v2.TrustObservation{
        .observer = observer_opt orelse return DecodeError.MissingField,
        .about = about_opt orelse return DecodeError.MissingField,
        .axes = axes_slice,
        .observed_at = observed_at,
        .context = context_opt,
    };
    return .{
        .obs = obs,
        .axes = axes_slice,
        .observer = obs.observer,
        .about = obs.about,
    };
}

// ============================================================================
// §13.7 ball.inscription — encoder + decoder
// ============================================================================

pub fn encodeInscription(allocator: Allocator, ins: v2.Inscription) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = 2; // surface, placement always present
    if (ins.note != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted: "type"(4), "format-version"(14)
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Inscription.type_string);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Inscription.format_version));

    // Attributes sorted: "note"(4), "surface"(7), "placement"(9)
    if (ins.note) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "note");
        try zbor.builder.writeTextString(w, n);
    }
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "surface");
    try zbor.builder.writeTextString(w, ins.surface);
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "placement");
    try zbor.builder.writeTextString(w, ins.placement);
    return ai.toOwnedSlice();
}

pub fn decodeInscription(bytes: []const u8) !v2.Inscription {
    try assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);
    try skipCoreMap(bytes, &cursor);

    var surface_opt: ?[]const u8 = null;
    var placement: []const u8 = "auto";
    var note_opt: ?[]const u8 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "surface")) {
            surface_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "placement")) {
            placement = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "note")) {
            note_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }
    return .{
        .surface = surface_opt orelse return DecodeError.MissingField,
        .placement = placement,
        .note = note_opt,
    };
}

// ============================================================================
// §13.8 ball.mythos — encoder + decoder
// ============================================================================

pub fn encodeMythos(allocator: Allocator, m: v2.Mythos) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = m.synthesizes.len + m.inspired_by.len;
    if (m.about != null) ac += 1;
    if (m.form != null) ac += 1;
    if (m.body != null) ac += 1;
    if (m.true_name != null) ac += 1;
    if (m.discovered_in != null) ac += 1;
    if (m.author != null) ac += 1;
    if (m.authored_at != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core fields: is-genesis (bool), predecessor (optional 32 bytes)
    // Keys sorted: "type"(4), "about" is attr not core. Core: "type"(4),
    //   "is-genesis"(10), "predecessor"(11) (optional), "format-version"(14)
    const core_len: u64 = if (m.predecessor != null) 4 else 3;
    try zbor.builder.writeMap(w, core_len);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Mythos.type_string);
    try zbor.builder.writeTextString(w, "is-genesis");
    if (m.is_genesis) try zbor.builder.writeTrue(w) else try zbor.builder.writeFalse(w);
    if (m.predecessor) |pred| {
        try zbor.builder.writeTextString(w, "predecessor");
        try zbor.builder.writeByteString(w, &pred);
    }
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Mythos.format_version));

    // Attributes sorted by label length then lex:
    // "body"(4), "form"(4), "about"(5) — len4: "body" < "form" lex
    // "author"(6), "true-name"(9), "authored-at"(11), "discovered-in"(13),
    // "inspired-by"(11), "synthesizes"(11) — len11: "authored-at" < "inspired-by" < "synthesizes" lex
    if (m.body) |b| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "body");
        try zbor.builder.writeTextString(w, b);
    }
    if (m.form) |f| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "form");
        try zbor.builder.writeTextString(w, f);
    }
    if (m.about) |ab| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "about");
        try zbor.builder.writeByteString(w, &ab);
    }
    if (m.author) |au| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "author");
        try zbor.builder.writeByteString(w, &au);
    }
    if (m.true_name) |tn| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "true-name");
        try zbor.builder.writeTextString(w, tn);
    }
    if (m.authored_at) |t| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "authored-at");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(t));
    }
    if (m.discovered_in) |di| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "discovered-in");
        try zbor.builder.writeByteString(w, &di);
    }
    for (m.inspired_by) |ib| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "inspired-by");
        try zbor.builder.writeByteString(w, &ib);
    }
    for (m.synthesizes) |sy| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "synthesizes");
        try zbor.builder.writeByteString(w, &sy);
    }
    return ai.toOwnedSlice();
}

pub fn decodeMythos(allocator: Allocator, bytes: []const u8) !struct {
    mythos: v2.Mythos,
    synthesizes: [][32]u8,
    inspired_by: [][32]u8,
} {
    try assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);

    dcbor.expectTag(bytes, &cursor, dcbor.Tag.leaf) catch |e| return mapDecodeError(e);
    const core_n = dcbor.readMapHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
    var is_genesis: bool = false;
    var predecessor: ?[32]u8 = null;
    var ci: u64 = 0;
    while (ci < core_n) : (ci += 1) {
        const k = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, k, "is-genesis")) {
            // Read bool: major 7, simple value 20=false, 21=true
            if (cursor >= bytes.len) return DecodeError.Truncated;
            const b = bytes[cursor];
            cursor += 1;
            if (b == 0xF5) is_genesis = true
            else if (b == 0xF4) is_genesis = false
            else return DecodeError.InvalidValue;
        } else if (std.mem.eql(u8, k, "predecessor")) {
            const bs = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (bs.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, bs);
            predecessor = fp;
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    var about: ?[32]u8 = null;
    var form: ?[]const u8 = null;
    var body: ?[]const u8 = null;
    var true_name: ?[]const u8 = null;
    var discovered_in: ?[32]u8 = null;
    var author: ?[32]u8 = null;
    var authored_at: ?i64 = null;
    var syn_list = std.ArrayListUnmanaged([32]u8).empty;
    defer syn_list.deinit(allocator);
    var insp_list = std.ArrayListUnmanaged([32]u8).empty;
    defer insp_list.deinit(allocator);

    var aii: u64 = 0;
    while (aii < attr_count) : (aii += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "about")) {
            const bs = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (bs.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, bs);
            about = fp;
        } else if (std.mem.eql(u8, key, "form")) {
            form = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "body")) {
            body = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "true-name")) {
            true_name = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "discovered-in")) {
            const bs = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (bs.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, bs);
            discovered_in = fp;
        } else if (std.mem.eql(u8, key, "author")) {
            const bs = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (bs.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, bs);
            author = fp;
        } else if (std.mem.eql(u8, key, "authored-at")) {
            dcbor.expectTag(bytes, &cursor, dcbor.Tag.epoch_time) catch |e| return mapDecodeError(e);
            const ts = dcbor.readUint(bytes, &cursor) catch |e| return mapDecodeError(e);
            authored_at = @intCast(ts);
        } else if (std.mem.eql(u8, key, "synthesizes")) {
            const bs = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (bs.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, bs);
            try syn_list.append(allocator, fp);
        } else if (std.mem.eql(u8, key, "inspired-by")) {
            const bs = dcbor.readBytes(bytes, &cursor) catch |e| return mapDecodeError(e);
            if (bs.len != 32) return DecodeError.InvalidValue;
            var fp: [32]u8 = undefined;
            @memcpy(&fp, bs);
            try insp_list.append(allocator, fp);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }

    const syn_slice = try syn_list.toOwnedSlice(allocator);
    const insp_slice = try insp_list.toOwnedSlice(allocator);
    return .{
        .mythos = .{
            .is_genesis = is_genesis,
            .predecessor = predecessor,
            .about = about,
            .form = form,
            .body = body,
            .true_name = true_name,
            .discovered_in = discovered_in,
            .synthesizes = syn_slice,
            .inspired_by = insp_slice,
            .author = author,
            .authored_at = authored_at,
        },
        .synthesizes = syn_slice,
        .inspired_by = insp_slice,
    };
}

// ============================================================================
// §13.9 ball.archiform — encoder + decoder
// ============================================================================

pub fn encodeArchiform(allocator: Allocator, ar: v2.Archiform) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = 1; // form always present
    if (ar.tradition != null) ac += 1;
    if (ar.parent_form != null) ac += 1;
    if (ar.note != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted: "type"(4), "format-version"(14)
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Archiform.type_string);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Archiform.format_version));

    // Attributes sorted: "note"(4), "form"(4), "tradition"(9) — len4: "form" < "note" lex
    // "parent-form"(11), "tradition"(9)
    // len sorted: "form"(4), "note"(4) — "form" < "note", "tradition"(9), "parent-form"(11)
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "form");
    try zbor.builder.writeTextString(w, ar.form);
    if (ar.note) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "note");
        try zbor.builder.writeTextString(w, n);
    }
    if (ar.tradition) |tr| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "tradition");
        try zbor.builder.writeTextString(w, tr);
    }
    if (ar.parent_form) |pf| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "parent-form");
        try zbor.builder.writeTextString(w, pf);
    }
    return ai.toOwnedSlice();
}

pub fn decodeArchiform(bytes: []const u8) !v2.Archiform {
    try assertCanonical(bytes);
    var cursor: usize = 0;
    const attr_count = try readEnvelopeHeader(bytes, &cursor);
    try skipCoreMap(bytes, &cursor);

    var form_opt: ?[]const u8 = null;
    var tradition: ?[]const u8 = null;
    var parent_form: ?[]const u8 = null;
    var note: ?[]const u8 = null;

    var ai: u64 = 0;
    while (ai < attr_count) : (ai += 1) {
        const arr_n = dcbor.readArrayHeader(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (arr_n != 2) return DecodeError.InvalidValue;
        const key = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        if (std.mem.eql(u8, key, "form")) {
            form_opt = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "tradition")) {
            tradition = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "parent-form")) {
            parent_form = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else if (std.mem.eql(u8, key, "note")) {
            note = dcbor.readText(bytes, &cursor) catch |e| return mapDecodeError(e);
        } else {
            dcbor.skipItem(bytes, &cursor) catch |e| return mapDecodeError(e);
        }
    }
    return .{
        .form = form_opt orelse return DecodeError.MissingField,
        .tradition = tradition,
        .parent_form = parent_form,
        .note = note,
    };
}

// ============================================================================
// Tests
// ============================================================================

// ============================================================================
// Story 1.3 — palace envelope round-trip tests (≥5 assertions per AC1/NFR16)
// ============================================================================

test "encodeLayout round-trip" {
    const allocator = std.testing.allocator;
    const p1 = v2.Placement{
        .child_fp = [_]u8{0x11} ** 32,
        .position = .{ 1.0, 2.0, 3.0 },
        .facing = .{ .qx = 0.0, .qy = 0.0, .qz = 0.0, .qw = 1.0 },
    };
    const p2 = v2.Placement{
        .child_fp = [_]u8{0x22} ** 32,
        .position = .{ -1.0, 0.5, 0.0 },
        .facing = .{ .qx = 0.5, .qy = 0.5, .qz = 0.5, .qw = 0.5 },
    };
    const placements = [_]v2.Placement{ p1, p2 };
    const layout = v2.Layout{ .placements = &placements, .note = "test arrangement" };
    const bytes = try encodeLayout(allocator, layout);
    defer allocator.free(bytes);

    // Outer tag bytes
    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]); // tag 200
    try std.testing.expectEqual(@as(u8, 0xC8), bytes[1]);

    // Type string present in bytes
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.layout") != null);
    // Both child fingerprints present
    try std.testing.expect(std.mem.indexOfScalar(u8, bytes, 0x11) != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, bytes, 0x22) != null);
    // Note present
    try std.testing.expect(std.mem.indexOf(u8, bytes, "test arrangement") != null);

    // Round-trip decode
    var result = try decodeLayout(allocator, bytes);
    defer allocator.free(result.placements);
    defer if (result.note_buf) |nb| allocator.free(nb);

    try std.testing.expectEqual(@as(usize, 2), result.placements.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x11} ** 32, &result.placements[0].child_fp);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x22} ** 32, &result.placements[1].child_fp);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.placements[0].position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.placements[0].facing.qw, 0.001);
    try std.testing.expect(result.layout.note != null);
}

test "encodeTimeline round-trip" {
    const allocator = std.testing.allocator;
    var heads = [_][32]u8{
        [_]u8{0xAA} ** 32,
        [_]u8{0xBB} ** 32,
    };
    const tl = v2.Timeline{
        .palace_fp = [_]u8{0x01} ** 32,
        .head_hashes = &heads,
        .note = "genesis",
    };
    const bytes = try encodeTimeline(allocator, tl);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xC8), bytes[1]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.timeline") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "head-hashes") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "genesis") != null);

    var result = try decodeTimeline(allocator, bytes);
    defer allocator.free(result.head_hashes);
    defer if (result.note_buf) |nb| allocator.free(nb);

    try std.testing.expectEqualSlices(u8, &[_]u8{0x01} ** 32, &result.palace_fp);
    // AC3: both heads preserved
    try std.testing.expectEqual(@as(usize, 2), result.head_hashes.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xAA} ** 32, &result.head_hashes[0]);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xBB} ** 32, &result.head_hashes[1]);
    try std.testing.expect(result.timeline.note != null);
}

test "encodeTimeline AC3: concurrent heads cardinality ≥2" {
    const allocator = std.testing.allocator;
    var heads = [_][32]u8{
        [_]u8{0xCC} ** 32,
        [_]u8{0xDD} ** 32,
        [_]u8{0xEE} ** 32,
    };
    const tl = v2.Timeline{
        .palace_fp = [_]u8{0x02} ** 32,
        .head_hashes = &heads,
    };
    const bytes = try encodeTimeline(allocator, tl);
    defer allocator.free(bytes);
    const result = try decodeTimeline(allocator, bytes);
    defer allocator.free(result.head_hashes);
    defer if (result.note_buf) |nb| allocator.free(nb);

    try std.testing.expectEqual(@as(usize, 3), result.head_hashes.len);
    // Set membership check for all 3 heads
    var found_cc = false;
    var found_dd = false;
    var found_ee = false;
    for (result.head_hashes) |hh| {
        if (hh[0] == 0xCC) found_cc = true;
        if (hh[0] == 0xDD) found_dd = true;
        if (hh[0] == 0xEE) found_ee = true;
    }
    try std.testing.expect(found_cc);
    try std.testing.expect(found_dd);
    try std.testing.expect(found_ee);
}

// Dreamball-y4t.15 removed the "encodeAction round-trip" and "encodeAction
// AC4: multi-parent + deps + nacks" tests along with the v3 `encodeAction`
// they exercised. See "decodeAction rejects format-version 3" below for the
// regression test proving a v3 envelope now fails cleanly on decode.

// ----------------------------------------------------------------------------
// A2 — v4 ball.action codec (open kind + opaque body + HLC). These exercise
// the encodeActionV4 / decodeAction v4 path — the only format the core
// substrate supports since v3 was dropped (Dreamball-y4t.15).
// PROTOCOL.md §16.7/§17/§18.
// ----------------------------------------------------------------------------

test "encodeActionV4 round-trip with body (7-key core map)" {
    const allocator = std.testing.allocator;
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    // Opaque consumer payload: a canonical CBOR array [1, 2].
    const body = [_]u8{ 0x82, 0x01, 0x02 };
    const a = v2.Action{
        .kind = "worldtree.kanban-card.move",
        .parent_hashes = &parents,
        .actor = [_]u8{0x20} ** 32,
        .body = &body,
        .hlc = .{ 1_700_000_000_000, 7 },
    };
    const bytes = try encodeActionV4(allocator, a);
    defer allocator.free(bytes);

    // v4 markers: open `kind`, `format-version` 4, and NO legacy `action-kind`.
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.action") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "worldtree.kanban-card.move") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "action-kind") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "hlc") != null);
    // Encoder output must itself be canonical.
    try assertCanonical(bytes);

    var result = try decodeAction(allocator, bytes);
    defer allocator.free(result.parent_hashes);
    defer allocator.free(result.deps);
    defer allocator.free(result.nacks);

    try std.testing.expectEqualStrings("worldtree.kanban-card.move", result.action.kind);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x20} ** 32, &result.action.actor);
    try std.testing.expectEqual(@as(usize, 1), result.parent_hashes.len);
    try std.testing.expect(result.action.body != null);
    try std.testing.expectEqualSlices(u8, &body, result.action.body.?);
    try std.testing.expectEqual(@as(u64, 1_700_000_000_000), result.action.hlc[0]);
    try std.testing.expectEqual(@as(u64, 7), result.action.hlc[1]);

    // Re-encode the decoded action and confirm byte-identical canonical output.
    const reencoded = try encodeActionV4(allocator, result.action);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, bytes, reencoded);
}

test "encodeActionV4 round-trip without body (6-key core map)" {
    const allocator = std.testing.allocator;
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    const a = v2.Action{
        .kind = "palace.minted",
        .parent_hashes = &parents,
        .actor = [_]u8{0x01} ** 32,
        .hlc = .{ 42, 0 },
    };
    const bytes = try encodeActionV4(allocator, a);
    defer allocator.free(bytes);
    try assertCanonical(bytes);

    const result = try decodeAction(allocator, bytes);
    defer allocator.free(result.parent_hashes);
    defer allocator.free(result.deps);
    defer allocator.free(result.nacks);

    try std.testing.expectEqualStrings("palace.minted", result.action.kind);
    try std.testing.expectEqual(@as(?[]const u8, null), result.action.body);
    try std.testing.expectEqual(@as(u64, 42), result.action.hlc[0]);
    try std.testing.expectEqual(@as(u64, 0), result.action.hlc[1]);

    const reencoded = try encodeActionV4(allocator, result.action);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, bytes, reencoded);
}

test "encodeActionV4 multi-parent + deps + nacks + target-fp + timestamp" {
    const allocator = std.testing.allocator;
    var parents = [_][32]u8{ [_]u8{0x01} ** 32, [_]u8{0x02} ** 32 };
    const deps = [_]v2.ActionRef{[_]u8{0x0D} ** 32};
    const nacks = [_]v2.ActionRef{[_]u8{0x0F} ** 32};
    const a = v2.Action{
        .kind = "myapp.document.archive",
        .parent_hashes = &parents,
        .actor = [_]u8{0x03} ** 32,
        .hlc = .{ 9_000_000_000_000, 65_535 },
        .target_fp = [_]u8{0x30} ** 32,
        .timestamp = 1_700_000_000,
        .deps = &deps,
        .nacks = &nacks,
    };
    const bytes = try encodeActionV4(allocator, a);
    defer allocator.free(bytes);

    const result = try decodeAction(allocator, bytes);
    defer allocator.free(result.parent_hashes);
    defer allocator.free(result.deps);
    defer allocator.free(result.nacks);

    try std.testing.expectEqual(@as(usize, 2), result.parent_hashes.len);
    try std.testing.expectEqual(@as(usize, 1), result.deps.len);
    try std.testing.expectEqual(@as(usize, 1), result.nacks.len);
    try std.testing.expectEqual(@as(u64, 9_000_000_000_000), result.action.hlc[0]);
    try std.testing.expectEqual(@as(u64, 65_535), result.action.hlc[1]);
    try std.testing.expect(result.action.target_fp != null);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), result.action.timestamp.?);
}

test "decodeAction rejects format-version 3 (v3 palace profile removed from core, Dreamball-y4t.15)" {
    // Hand-built canonical v3 core map — the closed palace profile (5-key
    // core map: type, actor, action-kind, parent-hashes, format-version). No
    // encoder for this shape exists in the core substrate any more (it lives
    // only in src/cli/internal/palace_action_v3.zig, for the palace CLI), so
    // this test builds the bytes directly with zbor primitives to prove
    // decodeAction still branches on format-version FIRST (PROTOCOL.md
    // §16.7) and rejects a structurally well-formed v3 envelope cleanly,
    // rather than silently misparsing it as v4.
    const allocator = std.testing.allocator;
    var ai = std.Io.Writer.Allocating.init(allocator);
    defer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeArray(w, 1); // core only
    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 5);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Action.type_string);
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &([_]u8{0x20} ** 32));
    try zbor.builder.writeTextString(w, "action-kind");
    try zbor.builder.writeTextString(w, "true-naming");
    try zbor.builder.writeTextString(w, "parent-hashes");
    try zbor.builder.writeArray(w, 1);
    try zbor.builder.writeByteString(w, &([_]u8{0x10} ** 32));
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @as(u64, 3));
    const bytes = try ai.toOwnedSlice();
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "action-kind") != null);

    try std.testing.expectError(DecodeError.UnsupportedFormatVersion, decodeAction(allocator, bytes));
}

test "encodeActionV4 rejects a non-canonical body" {
    const allocator = std.testing.allocator;
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    // Non-canonical CBOR: uint 0 written in 2-byte form (0x18 0x00) instead of
    // the shortest 0x00. assertCanonical must reject before anything is emitted.
    const bad_body = [_]u8{ 0x18, 0x00 };
    const a = v2.Action{
        .kind = "x.y.z",
        .parent_hashes = &parents,
        .actor = [_]u8{0x01} ** 32,
        .body = &bad_body,
        .hlc = .{ 1, 0 },
    };
    try std.testing.expectError(DecodeError.NonCanonicalInteger, encodeActionV4(allocator, a));
}

// ----------------------------------------------------------------------------
// A3 — validation on decode (canonical body + required fields). These tests
// hand-build v4 core maps directly so a malformed envelope can bypass the
// encoder's own checks and reach decodeAction. The map keys are emitted in
// dCBOR canonical order — hlc(3), body(4), kind(4), type(4), actor(5),
// parent-hashes(13), format-version(14) — so the outer assertCanonical gate
// passes and each test isolates the specific decode-side rule under test.
// ----------------------------------------------------------------------------

const A3CoreOpts = struct {
    include_hlc: bool = true,
    hlc_arity: u64 = 2,
    include_kind: bool = true,
    kind: []const u8 = "x.y.z",
    body: ?[]const u8 = null,
    include_actor: bool = true,
    include_fv: bool = true,
    fv: u64 = v2.Action.format_version,
};

/// Build a v4 `ball.action` envelope (zero attributes) with a hand-laid core
/// map, in canonical key order, honouring `opts`. Used only by the A3 tests.
fn buildA3V4Core(allocator: Allocator, opts: A3CoreOpts) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeArray(w, 1); // core only, zero attributes

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    var n: u64 = 2; // "type" + "parent-hashes" always present
    if (opts.include_hlc) n += 1;
    if (opts.body != null) n += 1;
    if (opts.include_kind) n += 1;
    if (opts.include_actor) n += 1;
    if (opts.include_fv) n += 1;
    try zbor.builder.writeMap(w, n);

    if (opts.include_hlc) {
        try zbor.builder.writeTextString(w, "hlc");
        try zbor.builder.writeArray(w, opts.hlc_arity);
        var i: u64 = 0;
        while (i < opts.hlc_arity) : (i += 1) try zbor.builder.writeInt(w, @as(u64, 0));
    }
    if (opts.body) |b| {
        try zbor.builder.writeTextString(w, "body");
        try zbor.builder.writeByteString(w, b);
    }
    if (opts.include_kind) {
        try zbor.builder.writeTextString(w, "kind");
        try zbor.builder.writeTextString(w, opts.kind);
    }
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Action.type_string);
    if (opts.include_actor) {
        try zbor.builder.writeTextString(w, "actor");
        try zbor.builder.writeByteString(w, &([_]u8{0} ** 32));
    }
    try zbor.builder.writeTextString(w, "parent-hashes");
    try zbor.builder.writeArray(w, 0);
    if (opts.include_fv) {
        try zbor.builder.writeTextString(w, "format-version");
        try zbor.builder.writeInt(w, opts.fv);
    }
    return ai.toOwnedSlice();
}

test "A3: v4 empty kind is a decode error" {
    const allocator = std.testing.allocator;
    // §18.1 — zero-length kind. The envelope is otherwise canonical and
    // complete, so only the empty-kind rule can reject it.
    const bytes = try buildA3V4Core(allocator, .{ .kind = "" });
    defer allocator.free(bytes);
    try assertCanonical(bytes); // outer envelope is canonical; rejection is decode-side
    try std.testing.expectError(DecodeError.InvalidValue, decodeAction(allocator, bytes));
}

test "A3: v4 non-canonical body is rejected" {
    const allocator = std.testing.allocator;
    // Body bytes = uint 0 in non-minimal 2-byte form (0x18 0x00). Wrapped in a
    // byte string, the outer assertCanonical walks past it without inspecting
    // the inner bytes, so the decode-side body gate is the only thing that can
    // catch it (D-041/D-043).
    const bad_body = [_]u8{ 0x18, 0x00 };
    const bytes = try buildA3V4Core(allocator, .{ .body = &bad_body });
    defer allocator.free(bytes);
    try assertCanonical(bytes); // outer envelope passes — body is opaque here
    try std.testing.expectError(DecodeError.NonCanonicalInteger, decodeAction(allocator, bytes));
}

test "A3: v4 absent body decodes cleanly after A3" {
    const allocator = std.testing.allocator;
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    const a = v2.Action{
        .kind = "myapp.thing.do",
        .parent_hashes = &parents,
        .actor = [_]u8{0x01} ** 32,
        .hlc = .{ 7, 1 },
    };
    const bytes = try encodeActionV4(allocator, a);
    defer allocator.free(bytes);
    // The `if (decoded_body) |b|` guard must not misfire on a null body.
    const result = try decodeAction(allocator, bytes);
    defer allocator.free(result.parent_hashes);
    defer allocator.free(result.deps);
    defer allocator.free(result.nacks);
    try std.testing.expectEqual(@as(?[]const u8, null), result.action.body);
    try std.testing.expectEqualStrings("myapp.thing.do", result.action.kind);
}

test "A3: v4 canonical body passes decode" {
    const allocator = std.testing.allocator;
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    // Minimal known-good canonical CBOR body: the integer 1 (0x01).
    const body = [_]u8{0x01};
    const a = v2.Action{
        .kind = "myapp.thing.do",
        .parent_hashes = &parents,
        .actor = [_]u8{0x01} ** 32,
        .body = &body,
        .hlc = .{ 7, 1 },
    };
    const bytes = try encodeActionV4(allocator, a);
    defer allocator.free(bytes);
    const result = try decodeAction(allocator, bytes);
    defer allocator.free(result.parent_hashes);
    defer allocator.free(result.deps);
    defer allocator.free(result.nacks);
    try std.testing.expect(result.action.body != null);
    try std.testing.expectEqualSlices(u8, &body, result.action.body.?);
}

test "A3: v4 missing kind returns MissingField" {
    const allocator = std.testing.allocator;
    const bytes = try buildA3V4Core(allocator, .{ .include_kind = false });
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.MissingField, decodeAction(allocator, bytes));
}

test "A3: v4 missing actor returns MissingField" {
    const allocator = std.testing.allocator;
    const bytes = try buildA3V4Core(allocator, .{ .include_actor = false });
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.MissingField, decodeAction(allocator, bytes));
}

test "A3: v4 missing hlc returns MissingField" {
    const allocator = std.testing.allocator;
    const bytes = try buildA3V4Core(allocator, .{ .include_hlc = false });
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.MissingField, decodeAction(allocator, bytes));
}

test "A3: v4 missing format-version returns MissingField" {
    const allocator = std.testing.allocator;
    const bytes = try buildA3V4Core(allocator, .{ .include_fv = false });
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.MissingField, decodeAction(allocator, bytes));
}

test "A3: v4 hlc with 1 element returns InvalidValue" {
    const allocator = std.testing.allocator;
    const bytes = try buildA3V4Core(allocator, .{ .hlc_arity = 1 });
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.InvalidValue, decodeAction(allocator, bytes));
}

test "A3: v4 hlc with 3 elements returns InvalidValue" {
    const allocator = std.testing.allocator;
    const bytes = try buildA3V4Core(allocator, .{ .hlc_arity = 3 });
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.InvalidValue, decodeAction(allocator, bytes));
}

test "A3: unknown format-version (5) returns InvalidValue" {
    const allocator = std.testing.allocator;
    const bytes = try buildA3V4Core(allocator, .{ .fv = 5 });
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.InvalidValue, decodeAction(allocator, bytes));
}

// Dreamball-y4t.15 removed "A3: v3 valid action-kind still decodes" and "A3:
// v3 unknown action-kind returns InvalidValue" — both are superseded by
// "decodeAction rejects format-version 3" above, since a v3 envelope is now
// rejected outright regardless of its action-kind content.

test "encodeAqueduct round-trip" {
    const allocator = std.testing.allocator;
    const aq = v2.Aqueduct{
        .from = [_]u8{0xAA} ** 32,
        .to = [_]u8{0xBB} ** 32,
        .kind = "gaze",
        .capacity = 0.85,
        .strength = 0.12,
        .resistance = 0.30,
        .capacitance = 0.55,
        .conductance = 0.368,
        .phase = .resonant,
        .last_traversed = 1_700_000_000,
    };
    const bytes = try encodeAqueduct(allocator, aq);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.aqueduct") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "gaze") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "resistance") != null);

    const decoded = try decodeAqueduct(allocator, bytes);

    try std.testing.expectEqualSlices(u8, &[_]u8{0xAA} ** 32, &decoded.from);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xBB} ** 32, &decoded.to);
    try std.testing.expectEqualStrings("gaze", decoded.kind);
    try std.testing.expectApproxEqAbs(@as(f32, 0.12), decoded.strength, 0.001);
    try std.testing.expect(decoded.conductance != null);
    try std.testing.expectEqual(v2.AqueductPhase.resonant, decoded.phase.?);
}

test "encodeAqueduct AC5: float discipline half/single" {
    const allocator = std.testing.allocator;
    // resistance = 0.3 is NOT lossless in f16 (0.3 has no exact f16 rep)
    // conductance = 0.368 also not lossless in f16
    // So both should be single (#7.26 = 0xFA prefix)
    const aq = v2.Aqueduct{
        .from = [_]u8{0xAA} ** 32,
        .to = [_]u8{0xBB} ** 32,
        .kind = "visit",
        .resistance = 0.3,
        .conductance = 0.368,
    };
    const bytes = try encodeAqueduct(allocator, aq);
    defer allocator.free(bytes);

    // Find "resistance" label in bytes; the float value follows immediately after the 2-element array wrapping it
    const res_label = "resistance";
    const res_idx = std.mem.indexOf(u8, bytes, res_label) orelse return error.TestFailed;
    // After the text string for "resistance", the next byte is the float value
    const float_byte = bytes[res_idx + res_label.len];
    // 0xFA = major 7, info 26 (single-precision #7.26)
    // 0xF9 = major 7, info 25 (half-precision #7.25)
    // 0.3 is not exactly representable in f16, so must be 0xFA
    try std.testing.expectEqual(@as(u8, 0xFA), float_byte);

    // capacity=0.0 (default) IS lossless in f16 (0xF9)
    const aq2 = v2.Aqueduct{
        .from = [_]u8{0x01} ** 32,
        .to = [_]u8{0x02} ** 32,
        .kind = "gaze",
        .capacity = 0.0, // exactly 0.0 — lossless in f16
    };
    const bytes2 = try encodeAqueduct(allocator, aq2);
    defer allocator.free(bytes2);
    const cap_idx = std.mem.indexOf(u8, bytes2, "capacity") orelse return error.TestFailed;
    const cap_float_byte = bytes2[cap_idx + "capacity".len];
    // 0.0 is lossless in f16 → 0xF9
    try std.testing.expectEqual(@as(u8, 0xF9), cap_float_byte);
}

test "encodeAqueduct AC5: conductance absent (TC16)" {
    const allocator = std.testing.allocator;
    const aq = v2.Aqueduct{
        .from = [_]u8{0x01} ** 32,
        .to = [_]u8{0x02} ** 32,
        .kind = "transmit",
        .conductance = null, // absent per TC16
    };
    const bytes = try encodeAqueduct(allocator, aq);
    defer allocator.free(bytes);
    // "conductance" label must NOT appear in bytes
    try std.testing.expectEqual(@as(?usize, null), std.mem.indexOf(u8, bytes, "conductance"));
    const decoded = try decodeAqueduct(allocator, bytes);
    try std.testing.expectEqual(@as(?f32, null), decoded.conductance);
}

test "encodeElementTag round-trip" {
    const allocator = std.testing.allocator;
    const et = v2.ElementTag{
        .element = "wood",
        .phase = "nourishing",
        .note = "growth energy",
    };
    const bytes = try encodeElementTag(allocator, et);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.element-tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "wood") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "nourishing") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "growth energy") != null);

    const decoded = try decodeElementTag(bytes);
    try std.testing.expectEqualStrings("wood", decoded.element);
    try std.testing.expectEqualStrings("nourishing", decoded.phase.?);
    try std.testing.expectEqualStrings("growth energy", decoded.note.?);
}

test "encodeElementTag phase absent round-trip" {
    const allocator = std.testing.allocator;
    const et = v2.ElementTag{ .element = "fire" };
    const bytes = try encodeElementTag(allocator, et);
    defer allocator.free(bytes);
    const decoded = try decodeElementTag(bytes);
    try std.testing.expectEqualStrings("fire", decoded.element);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.phase);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.note);
}

test "encodeTrustObservation round-trip" {
    const allocator = std.testing.allocator;
    const axes = [_]v2.TrustAxis{
        .{ .name = "careful", .value = 0.78, .range = .{ 0.0, 1.0 } },
        .{ .name = "generous", .value = 0.61, .range = .{ 0.0, 1.0 } },
    };
    const to = v2.TrustObservation{
        .observer = [_]u8{0xAA} ** 32,
        .about = [_]u8{0xBB} ** 32,
        .axes = &axes,
        .observed_at = 1_700_000_001,
        .context = "pair-programming",
    };
    const bytes = try encodeTrustObservation(allocator, to);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.trust-observation") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "careful") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "generous") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "pair-programming") != null);

    var result = try decodeTrustObservation(allocator, bytes);
    defer allocator.free(result.axes);

    try std.testing.expectEqualSlices(u8, &[_]u8{0xAA} ** 32, &result.observer);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xBB} ** 32, &result.about);
    try std.testing.expectEqual(@as(usize, 2), result.axes.len);
    try std.testing.expectEqualStrings("careful", result.axes[0].name);
    try std.testing.expectApproxEqAbs(@as(f64, 0.78), result.axes[0].value, 0.001);
    try std.testing.expectEqual(@as(i64, 1_700_000_001), result.obs.observed_at.?);
}

test "encodeInscription round-trip" {
    const allocator = std.testing.allocator;
    const ins = v2.Inscription{
        .surface = "scroll",
        .placement = "curator",
        .note = "east wall",
    };
    const bytes = try encodeInscription(allocator, ins);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.inscription") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "scroll") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "curator") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "east wall") != null);

    const decoded = try decodeInscription(bytes);
    try std.testing.expectEqualStrings("scroll", decoded.surface);
    try std.testing.expectEqualStrings("curator", decoded.placement);
    try std.testing.expectEqualStrings("east wall", decoded.note.?);
}

test "encodeInscription default placement round-trip" {
    const allocator = std.testing.allocator;
    const ins = v2.Inscription{ .surface = "tablet" };
    const bytes = try encodeInscription(allocator, ins);
    defer allocator.free(bytes);
    const decoded = try decodeInscription(bytes);
    try std.testing.expectEqualStrings("tablet", decoded.surface);
    try std.testing.expectEqualStrings("auto", decoded.placement);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.note);
}

test "encodeMythos round-trip genesis" {
    const allocator = std.testing.allocator;
    const m = v2.Mythos{
        .is_genesis = true,
        .form = "invocation",
        .body = "There is a giant cow beside the chaos abyss.",
        .true_name = "Audhumla",
        .author = [_]u8{0xCC} ** 32,
        .authored_at = 1_700_000_002,
    };
    const bytes = try encodeMythos(allocator, m);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.mythos") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Audhumla") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "invocation") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "is-genesis") != null);

    const result = try decodeMythos(allocator, bytes);
    defer allocator.free(result.synthesizes);
    defer allocator.free(result.inspired_by);

    try std.testing.expect(result.mythos.is_genesis);
    try std.testing.expectEqual(@as(?[32]u8, null), result.mythos.predecessor);
    try std.testing.expectEqualStrings("Audhumla", result.mythos.true_name.?);
    try std.testing.expectEqualStrings("invocation", result.mythos.form.?);
    try std.testing.expectEqual(@as(i64, 1_700_000_002), result.mythos.authored_at.?);
}

test "encodeMythos round-trip poetic (about present, synthesizes)" {
    const allocator = std.testing.allocator;
    var syn = [_][32]u8{ [_]u8{0x55} ** 32, [_]u8{0x66} ** 32 };
    const m = v2.Mythos{
        .is_genesis = false,
        .predecessor = [_]u8{0x44} ** 32,
        .about = [_]u8{0x77} ** 32,
        .form = "blurb",
        .body = "A brief myth.",
        .synthesizes = &syn,
    };
    const bytes = try encodeMythos(allocator, m);
    defer allocator.free(bytes);
    var result = try decodeMythos(allocator, bytes);
    defer allocator.free(result.synthesizes);
    defer allocator.free(result.inspired_by);

    try std.testing.expect(!result.mythos.is_genesis);
    try std.testing.expect(result.mythos.predecessor != null);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x44} ** 32, &result.mythos.predecessor.?);
    try std.testing.expect(result.mythos.about != null);
    try std.testing.expectEqual(@as(usize, 2), result.synthesizes.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x55} ** 32, &result.synthesizes[0]);
}

test "encodeArchiform round-trip" {
    const allocator = std.testing.allocator;
    const ar = v2.Archiform{
        .form = "library",
        .tradition = "hermetic",
        .parent_form = "atrium",
        .note = "catalogues rather than restricts",
    };
    const bytes = try encodeArchiform(allocator, ar);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "ball.archiform") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "library") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "hermetic") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "atrium") != null);

    const decoded = try decodeArchiform(bytes);
    try std.testing.expectEqualStrings("library", decoded.form);
    try std.testing.expectEqualStrings("hermetic", decoded.tradition.?);
    try std.testing.expectEqualStrings("atrium", decoded.parent_form.?);
    try std.testing.expectEqualStrings("catalogues rather than restricts", decoded.note.?);
}

test "encodeArchiform minimal round-trip" {
    const allocator = std.testing.allocator;
    const ar = v2.Archiform{ .form = "forge" };
    const bytes = try encodeArchiform(allocator, ar);
    defer allocator.free(bytes);
    const decoded = try decodeArchiform(bytes);
    try std.testing.expectEqualStrings("forge", decoded.form);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.tradition);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.parent_form);
}

test "AC2: dCBOR ordering — two encodeArchiform calls produce identical bytes" {
    const allocator = std.testing.allocator;
    // Same data, same ordering must produce identical bytes (ordering is deterministic)
    const ar = v2.Archiform{
        .form = "throne-room",
        .tradition = "shinto",
        .parent_form = "courtyard",
        .note = "ceremonial",
    };
    const b1 = try encodeArchiform(allocator, ar);
    defer allocator.free(b1);
    const b2 = try encodeArchiform(allocator, ar);
    defer allocator.free(b2);
    try std.testing.expectEqualSlices(u8, b1, b2);
}

test "AC2: dCBOR ordering — two encodeTimeline calls produce identical bytes" {
    const allocator = std.testing.allocator;
    var heads = [_][32]u8{ [_]u8{0x99} ** 32 };
    const tl = v2.Timeline{
        .palace_fp = [_]u8{0x88} ** 32,
        .head_hashes = &heads,
    };
    const b1 = try encodeTimeline(allocator, tl);
    defer allocator.free(b1);
    const b2 = try encodeTimeline(allocator, tl);
    defer allocator.free(b2);
    try std.testing.expectEqualSlices(u8, b1, b2);
}

test "AC6: truncated bytes return error for all 9 decoders" {
    const allocator = std.testing.allocator;
    const truncated = [_]u8{ 0xD8, 0xC8, 0x82 }; // tag 200, array(2) but then truncated

    // Layout
    try std.testing.expectError(error.Truncated, decodeLayout(allocator, &truncated));
    // Timeline
    try std.testing.expectError(error.Truncated, decodeTimeline(allocator, &truncated));
    // Action
    try std.testing.expectError(error.Truncated, decodeAction(allocator, &truncated));
    // Aqueduct
    try std.testing.expectError(error.Truncated, decodeAqueduct(allocator, &truncated));
    // ElementTag
    try std.testing.expectError(error.Truncated, decodeElementTag(&truncated));
    // TrustObservation
    try std.testing.expectError(error.Truncated, decodeTrustObservation(allocator, &truncated));
    // Inscription
    try std.testing.expectError(error.Truncated, decodeInscription(&truncated));
    // Mythos
    try std.testing.expectError(error.Truncated, decodeMythos(allocator, &truncated));
    // Archiform
    try std.testing.expectError(error.Truncated, decodeArchiform(&truncated));
}

test "AC6: empty bytes return error for all 9 decoders" {
    const allocator = std.testing.allocator;
    const empty = [_]u8{};
    try std.testing.expectError(error.Truncated, decodeLayout(allocator, &empty));
    try std.testing.expectError(error.Truncated, decodeTimeline(allocator, &empty));
    try std.testing.expectError(error.Truncated, decodeAction(allocator, &empty));
    try std.testing.expectError(error.Truncated, decodeAqueduct(allocator, &empty));
    try std.testing.expectError(error.Truncated, decodeElementTag(&empty));
    try std.testing.expectError(error.Truncated, decodeTrustObservation(allocator, &empty));
    try std.testing.expectError(error.Truncated, decodeInscription(&empty));
    try std.testing.expectError(error.Truncated, decodeMythos(allocator, &empty));
    try std.testing.expectError(error.Truncated, decodeArchiform(&empty));
}

test "encodeGuild produces tag-200 envelope with guild name + members" {
    const allocator = std.testing.allocator;
    const members = [_]v2.GuildMembership{
        .{ .member = .{ .bytes = [_]u8{0x11} ** 32 } },
        .{ .member = .{ .bytes = [_]u8{0x22} ** 32 }, .is_admin = true },
    };
    const guild: v2.Guild = .{
        .guild_name = "Hummingbirds",
        .keyspace_root_hash = [_]u8{0xBB} ** 32,
        .members = &members,
        .policy = .{},
    };
    const bytes = try encodeGuild(allocator, [_]u8{1} ** 32, [_]u8{2} ** 32, guild, &.{});
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len > 0);
    try std.testing.expectEqual(@as(u8, 0xD8), bytes[0]); // tag 200
    try std.testing.expectEqual(@as(u8, 0xC8), bytes[1]);
}

test "encodeRelic carries sealed-payload-hash + unlock-guild" {
    const allocator = std.testing.allocator;
    const relic: v2.Relic = .{
        .sealed_payload_hash = [_]u8{0xAA} ** 32,
        .unlock_guild = .{ .bytes = [_]u8{0xBB} ** 32 },
        .reveal_hint = "Look behind the mirror",
    };
    const bytes = try encodeRelic(allocator, [_]u8{1} ** 32, null, [_]u8{2} ** 32, relic, relic.reveal_hint, &.{});
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Look behind the mirror") != null);
}

test "encodeRelic with identity_pq bumps format-version to V3" {
    const allocator = std.testing.allocator;
    const relic: v2.Relic = .{
        .sealed_payload_hash = [_]u8{0xAA} ** 32,
        .unlock_guild = .{ .bytes = [_]u8{0xBB} ** 32 },
    };
    const pq_key: [protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8 = [_]u8{0xCC} ** protocol.ML_DSA_87_PUBLIC_KEY_LEN;
    const bytes = try encodeRelic(allocator, [_]u8{1} ** 32, pq_key, [_]u8{2} ** 32, relic, null, &.{});
    defer allocator.free(bytes);
    // The pubkey byte pattern should appear in the encoded envelope.
    try std.testing.expect(std.mem.indexOfScalar(u8, bytes, 0xCC) != null);
    // v3 single-byte uint (03) must appear after "format-version" label.
    const fv_idx = std.mem.indexOf(u8, bytes, "format-version") orelse unreachable;
    const fv_val = bytes[fv_idx + "format-version".len];
    try std.testing.expectEqual(@as(u8, 0x03), fv_val);
}

test "encodeTransmission with sender-identity bumps format-version to V3" {
    const allocator = std.testing.allocator;
    const fake_tool_envelope = [_]u8{ 0xD8, 0xC8, 0x01, 0x02, 0x03 };
    const sender_id: [32]u8 = [_]u8{0xAB} ** 32;
    const sender_pq: [protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8 = [_]u8{0xCD} ** protocol.ML_DSA_87_PUBLIC_KEY_LEN;
    const t: v2.Transmission = .{
        .tool_fp = .{ .bytes = [_]u8{0x11} ** 32 },
        .target_fp = .{ .bytes = [_]u8{0x22} ** 32 },
        .via_guild = .{ .bytes = [_]u8{0x33} ** 32 },
        .sender_identity = sender_id,
        .sender_identity_pq = sender_pq,
        .tool_envelope = &fake_tool_envelope,
    };
    const bytes = try encodeTransmission(allocator, t);
    defer allocator.free(bytes);
    // Core must advertise V3.
    const fv_idx = std.mem.indexOf(u8, bytes, "format-version") orelse unreachable;
    try std.testing.expectEqual(@as(u8, 0x03), bytes[fv_idx + "format-version".len]);
    // Both pubkey-pattern bytes appear in the envelope.
    try std.testing.expect(std.mem.indexOfScalar(u8, bytes, 0xAB) != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, bytes, 0xCD) != null);
}

test "encodeTransmission includes the tool envelope inline" {
    const allocator = std.testing.allocator;
    const fake_tool_envelope = [_]u8{ 0xD8, 0xC8, 0x01, 0x02, 0x03 };
    const t: v2.Transmission = .{
        .tool_fp = .{ .bytes = [_]u8{0x11} ** 32 },
        .target_fp = .{ .bytes = [_]u8{0x22} ** 32 },
        .via_guild = .{ .bytes = [_]u8{0x33} ** 32 },
        .tool_envelope = &fake_tool_envelope,
    };
    const bytes = try encodeTransmission(allocator, t);
    defer allocator.free(bytes);
    // The fake envelope bytes should appear inside.
    try std.testing.expect(std.mem.indexOf(u8, bytes, &fake_tool_envelope) != null);
}

// The encodeKnowledgeGraph / encodeEmotionalRegister tests moved to
// envelope.zig alongside the relocated codecs (now first-class DreamBall slots).

// ============================================================================
// Canonicality enforcement on decode — HIGH-1 (2026-04-24 code review).
// ============================================================================

test "HIGH-1: decodeAction rejects non-canonical map-key ordering" {
    // Build a ball.action envelope whose CORE MAP has two equal-length keys
    // emitted in lex-reversed order ("type"=4 < "actor"=5 is fine; the
    // violation is at len 5 where we swap "actor" and a fake same-length key).
    // We actually violate by emitting "format-version"(14) BEFORE
    // "parent-hashes"(13) — same lex prefix, wrong length order.
    const allocator = std.testing.allocator;
    var ai = std.Io.Writer.Allocating.init(allocator);
    defer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeArray(w, 1); // just core, zero attributes
    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 5);
    // Canonical order would be type(4), actor(5), action-kind(11),
    // parent-hashes(13), format-version(14). We emit format-version BEFORE
    // parent-hashes — a length-14 before a length-13 key.
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "ball.action");
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &([_]u8{0} ** 32));
    try zbor.builder.writeTextString(w, "action-kind");
    try zbor.builder.writeTextString(w, "palace-minted");
    try zbor.builder.writeTextString(w, "format-version"); // len 14 — emitted too soon
    try zbor.builder.writeInt(w, @as(u64, 3));
    try zbor.builder.writeTextString(w, "parent-hashes"); // len 13 — should have come first
    try zbor.builder.writeArray(w, 0);

    const bytes = try ai.toOwnedSlice();
    defer allocator.free(bytes);
    // decodeAction must reject at the canonicality gate.
    try std.testing.expectError(
        DecodeError.NonCanonicalInteger,
        decodeAction(allocator, bytes),
    );
}

test "HIGH-1: decodeTimeline rejects non-canonical nested uint" {
    // Build a valid timeline envelope, then mutate an inner uint to a padded form.
    const allocator = std.testing.allocator;
    var hh = [_][32]u8{[_]u8{0xAA} ** 32};
    const tl = v2.Timeline{
        .palace_fp = [_]u8{0x42} ** 32,
        .head_hashes = &hh,
        .note = null,
    };
    const good = try encodeTimeline(allocator, tl);
    defer allocator.free(good);
    // Baseline: canonical encode decodes OK.
    const ok_result = try decodeTimeline(allocator, good);
    allocator.free(ok_result.head_hashes);

    // Mutation: the format-version value (uint 3) is encoded as 0x03. Patch
    // it to the padded 2-byte form 0x18 0x03 and splice into a copy; this
    // makes every downstream offset shift by 1. Verify via the simpler
    // contract: any byte-for-byte corruption that introduces a non-canonical
    // head is rejected.  We corrupt the inner palace-fp byte-string len.
    //
    // Simpler approach: prepend a non-canonical uint to the stream.  Since
    // assertCanonical walks the entire byte slice, any prefix-added
    // non-canonical head triggers rejection.
    var buf = try allocator.alloc(u8, good.len + 2);
    defer allocator.free(buf);
    buf[0] = 0x18; // non-canonical 1-byte-follow for value 5
    buf[1] = 0x05;
    @memcpy(buf[2..], good);
    try std.testing.expectError(
        DecodeError.NonCanonicalInteger,
        decodeTimeline(allocator, buf),
    );
}

// ============================================================================
// Encoder → verifyCanonical meta-test — MEDIUM-5 (2026-04-24 code review).
//
// For every golden byte string the repo pins for the 9 palace-composition
// envelope types, assert:
//   (a) dcbor.verifyCanonical (or verifyCanonicalAllowFloats for float-
//       carrying envelopes) PASSES — proving the encoder emits canonical form.
//   (b) for at least one representative envelope, mutating the stream to
//       swap two equal-length map keys now causes verifyCanonical to REJECT.
//
// This is the meta-test that would have caught HIGH-1 pre-emptively — if
// the encoder ever regresses and starts emitting non-canonical bytes, this
// test fails at build time.
// ============================================================================

test "MEDIUM-5: encoder produces canonical bytes for every palace envelope" {
    const allocator = std.testing.allocator;

    // 1. layout (floats)
    {
        const placements = [_]v2.Placement{
            .{
                .child_fp = [_]u8{0x01} ** 32,
                .position = .{ 0.0, 0.0, 0.0 },
                .facing = .{ .qx = 0.0, .qy = 0.0, .qz = 0.0, .qw = 1.0 },
            },
        };
        const layout = v2.Layout{ .placements = &placements, .note = null };
        const bytes = try encodeLayout(allocator, layout);
        defer allocator.free(bytes);
        try dcbor.verifyCanonicalAllowFloats(bytes);
    }

    // 2. timeline (no floats)
    {
        var tl_hh = [_][32]u8{[_]u8{0xAA} ** 32};
        const tl = v2.Timeline{
            .palace_fp = [_]u8{0} ** 32,
            .head_hashes = &tl_hh,
            .note = null,
        };
        const bytes = try encodeTimeline(allocator, tl);
        defer allocator.free(bytes);
        try dcbor.verifyCanonical(bytes);
    }

    // 3. action (no floats) — v4 (v3 dropped from the core, Dreamball-y4t.15)
    {
        var act_ph = [_][32]u8{[_]u8{0x10} ** 32};
        const a = v2.Action{
            .kind = "palace.minted",
            .actor = [_]u8{0x01} ** 32,
            .parent_hashes = &act_ph,
            .hlc = .{ 0, 0 },
            .target_fp = null,
            .timestamp = null,
            .deps = &.{},
            .nacks = &.{},
        };
        const bytes = try encodeActionV4(allocator, a);
        defer allocator.free(bytes);
        try dcbor.verifyCanonical(bytes);
    }

    // 4. aqueduct (floats)
    {
        const aq = v2.Aqueduct{
            .from = [_]u8{0x11} ** 32,
            .to = [_]u8{0x22} ** 32,
            .kind = "visit",
            .capacity = 0.85,
            .strength = 0.12,
            .resistance = 0.30,
            .capacitance = 0.55,
            .conductance = 0.70,
            .phase = .resonant,
            .last_traversed = null,
        };
        const bytes = try encodeAqueduct(allocator, aq);
        defer allocator.free(bytes);
        try dcbor.verifyCanonicalAllowFloats(bytes);
    }

    // 5. element-tag (no floats)
    {
        const et = v2.ElementTag{ .element = "fire", .phase = "yang", .note = null };
        const bytes = try encodeElementTag(allocator, et);
        defer allocator.free(bytes);
        try dcbor.verifyCanonical(bytes);
    }

    // 6. trust-observation (floats)
    {
        const axes = [_]v2.TrustAxis{
            .{ .name = "careful", .value = 0.78 },
        };
        const to = v2.TrustObservation{
            .observer = [_]u8{0x01} ** 32,
            .about = [_]u8{0x02} ** 32,
            .axes = &axes,
            .observed_at = null,
            .context = null,
            .signatures = &.{},
        };
        const bytes = try encodeTrustObservation(allocator, to);
        defer allocator.free(bytes);
        try dcbor.verifyCanonicalAllowFloats(bytes);
    }

    // 7. inscription (no floats)
    {
        const ins = v2.Inscription{
            .surface = "scroll",
            .placement = "auto",
            .note = null,
        };
        const bytes = try encodeInscription(allocator, ins);
        defer allocator.free(bytes);
        try dcbor.verifyCanonical(bytes);
    }

    // 8. mythos (no floats; canonical-genesis shape)
    {
        const m = v2.Mythos{
            .is_genesis = true,
            .predecessor = null,
            .about = null,
            .form = "blurb",
            .body = "There is a giant cow beside the chaos abyss.",
            .true_name = "Audhumla",
            .discovered_in = null,
            .synthesizes = &.{},
            .inspired_by = &.{},
            .author = null,
            .authored_at = null,
        };
        const bytes = try encodeMythos(allocator, m);
        defer allocator.free(bytes);
        try dcbor.verifyCanonical(bytes);
    }

    // 9. archiform (no floats)
    {
        const ar = v2.Archiform{
            .form = "library",
            .tradition = "hermetic",
            .parent_form = "atrium",
            .note = null,
        };
        const bytes = try encodeArchiform(allocator, ar);
        defer allocator.free(bytes);
        try dcbor.verifyCanonical(bytes);
    }
}

test "MEDIUM-5: mutating an equal-length map-key pair causes verifyCanonical to reject" {
    // Use the timeline encoder's output (whose core map has keys sorted
    // canonically: type(4), palace-fp(9), format-version(14)) and find the
    // first pair of equal-length keys to swap.
    //
    // Simpler: hand-build a map with two equal-length keys in the WRONG
    // order and assert verifyCanonical rejects.  This is the shape a
    // corrupt / malicious encoder would produce.
    const allocator = std.testing.allocator;
    var ai = std.Io.Writer.Allocating.init(allocator);
    defer ai.deinit();
    const w = &ai.writer;
    // Canonical ordering: "aa" < "bb" (both len 2).  Emit reversed → violation.
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "bb");
    try zbor.builder.writeInt(w, @as(u64, 1));
    try zbor.builder.writeTextString(w, "aa");
    try zbor.builder.writeInt(w, @as(u64, 2));
    const bytes = try ai.toOwnedSlice();
    defer allocator.free(bytes);
    try std.testing.expectError(
        dcbor.ReadError.NonCanonicalInteger,
        dcbor.verifyCanonical(bytes),
    );
}

// ============================================================================
// A5 — Broader tamper matrix.
//
// A2 and A3 already cover: happy paths, HLC arity (AC1–2), unknown
// format-version (AC3), empty kind (AC4), missing-field matrix (AC9–12).
// A5 adds the remaining non-duplicate cases:
//   AC6  — truncated byte stream
//   AC7  — garbage bytes (not a valid envelope)
//   AC8  — non-canonical v4 7-key map ordering
//
// Dreamball-y4t.15 removed the original AC5 ("body key in a v3 envelope")
// and AC13 ("v3 golden fixtures round-trip") cases: v3 `ball.action` was
// dropped from the core substrate, so any v3 envelope — with or without a
// "body" key — is now rejected outright by the format-version dispatch
// (see "decodeAction rejects format-version 3" above), and the v3 golden
// fixtures no longer round-trip through this file at all (they moved to
// fixtures/goldens/palace-v3-manifest.json).
// ============================================================================

test "A5: decodeAction rejects truncated core map" {
    // AC6 — A valid v4 action truncated to half its byte length is incomplete
    // CBOR; assertCanonical fires DecodeError.Truncated before any field
    // parsing begins.
    const allocator = std.testing.allocator;
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    const a = v2.Action{
        .kind = "x.y.z",
        .parent_hashes = &parents,
        .actor = [_]u8{0x01} ** 32,
        .hlc = .{ 1, 0 },
    };
    const full = try encodeActionV4(allocator, a);
    defer allocator.free(full);
    const half = full[0 .. full.len / 2];
    try std.testing.expectError(DecodeError.Truncated, decodeAction(allocator, half));
}

test "A5: decodeAction rejects garbage bytes" {
    // AC7 — Three raw CBOR uint values with no envelope tag.  The very first
    // call, readEnvelopeHeader → expectTag, sees a non-tag major type and
    // returns DecodeError.UnexpectedMajorType; any DecodeError is acceptable.
    const allocator = std.testing.allocator;
    const bad = [_]u8{ 0x00, 0x01, 0x02 }; // uint 0, uint 1, uint 2 — no tag
    if (decodeAction(allocator, &bad)) |result| {
        // Must not succeed.
        allocator.free(result.parent_hashes);
        allocator.free(result.deps);
        allocator.free(result.nacks);
        return error.TestExpectedDecodeError;
    } else |_| {
        // Any DecodeError is correct; UnexpectedMajorType fires first here.
    }
}

test "A5: decodeAction rejects non-canonical v4 map key ordering" {
    // AC8 — 7-key v4 core map (includes "body") with "type" emitted before
    // "kind" at length 4.  Canonical len-4 order is "body" < "kind" < "type"
    // (lex).  "type" before "kind" violates it; assertCanonical returns
    // DecodeError.NonCanonicalInteger.  HIGH-1 covers the v3/5-key shape;
    // this AC covers the v4/7-key shape explicitly.
    const allocator = std.testing.allocator;
    var ai = std.Io.Writer.Allocating.init(allocator);
    defer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeArray(w, 1); // core only, zero attributes
    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 7);
    // Canonical len-3 first.
    try zbor.builder.writeTextString(w, "hlc");
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeInt(w, @as(u64, 1));
    try zbor.builder.writeInt(w, @as(u64, 0));
    // Len-4 keys emitted in violation order: body, TYPE, kind
    // ("type" before "kind" is the violation; "kind"(k=107) < "type"(t=116)).
    try zbor.builder.writeTextString(w, "body");
    try zbor.builder.writeByteString(w, &[_]u8{0x01}); // opaque body, canonical uint(1)
    try zbor.builder.writeTextString(w, "type"); // emitted too soon — violates body < kind < type
    try zbor.builder.writeTextString(w, v2.Action.type_string);
    try zbor.builder.writeTextString(w, "kind"); // should have come before "type"
    try zbor.builder.writeTextString(w, "x.y.z");
    // Remaining keys in canonical order.
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &([_]u8{0x01} ** 32));
    try zbor.builder.writeTextString(w, "parent-hashes");
    try zbor.builder.writeArray(w, 0);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, v2.Action.format_version);
    const bytes = try ai.toOwnedSlice();
    defer allocator.free(bytes);
    try std.testing.expectError(DecodeError.NonCanonicalInteger, decodeAction(allocator, bytes));
}

// Dreamball-y4t.15 removed "A5: v3 golden fixtures decode correctly
// (regression guard)" along with the v3 `encodeAction`/`ActionKind` it
// exercised. The three v3 action goldens it round-tripped
// (action_v3_single_parent / _multi_parent / _deps_nacks) are preserved
// byte-for-byte in fixtures/goldens/palace-v3-manifest.json for the Memory
// Palace extraction (Dreamball-etk); they no longer gate this file.

