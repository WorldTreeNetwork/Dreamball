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
// jelly.guild (§12.1.6) — a typed DreamBall envelope with a guild payload
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
    try zbor.builder.writeTextString(w, "jelly.dreamball.guild");
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
    try zbor.builder.writeTextString(w, "jelly.guild-policy");
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
// jelly.dreamball.relic (§12.1.4) — a typed DreamBall that wraps a sealed
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
    try zbor.builder.writeTextString(w, "jelly.dreamball.relic");
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
// jelly.transmission (§12.9) — receipt of a Tool transfer.
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
    try zbor.builder.writeTextString(w, "jelly.transmission");
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
// Minimal encoders for memory / knowledge-graph / emotional-register /
// interaction-set. v2 MVP uses them as nested envelopes inside Agent DreamBalls;
// the renderer consumes them via the generated TS types.
// ============================================================================

pub fn encodeMemory(allocator: Allocator, m: v2.Memory) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    const attribute_count: u64 = m.nodes.len + m.connections.len + @as(u64, if (m.last_updated != null) 1 else 0);
    try zbor.builder.writeArray(w, 1 + attribute_count);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 2);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "jelly.memory");
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

fn writeMemoryNode(w: *std.Io.Writer, n: v2.MemoryNode) !void {
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
    try zbor.builder.writeTextString(w, "jelly.memory-node");
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

fn writeMemoryConnection(w: *std.Io.Writer, e: v2.MemoryConnection) !void {
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
    try zbor.builder.writeTextString(w, "jelly.memory-connection");
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

pub fn encodeKnowledgeGraph(allocator: Allocator, kg: v2.KnowledgeGraph) ![]u8 {
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
    try zbor.builder.writeTextString(w, "jelly.knowledge-graph");
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

pub fn encodeEmotionalRegister(allocator: Allocator, er: v2.EmotionalRegister) ![]u8 {
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
    try zbor.builder.writeTextString(w, "jelly.emotional-register");
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(protocol.FORMAT_VERSION_V2));

    for (er.axes) |ax| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "axis");
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

// ============================================================================
// Tests
// ============================================================================

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

test "encodeMemory produces well-formed envelope" {
    const allocator = std.testing.allocator;
    const nodes = [_]v2.MemoryNode{
        .{ .id = 1, .content = "First memory" },
        .{ .id = 2, .content = "Second memory" },
    };
    const connections = [_]v2.MemoryConnection{
        .{ .from = 1, .to = 2, .kind = .temporal, .strength = 0.8 },
    };
    const m: v2.Memory = .{ .nodes = &nodes, .connections = &connections };
    const bytes = try encodeMemory(allocator, m);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "First memory") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "temporal") != null);
}

test "encodeKnowledgeGraph emits triples" {
    const allocator = std.testing.allocator;
    const triples = [_]v2.Triple{
        .{ .from = "curiosity", .label = "inclines-toward", .to = "new-things" },
    };
    const kg: v2.KnowledgeGraph = .{ .triples = &triples, .source = "test" };
    const bytes = try encodeKnowledgeGraph(allocator, kg);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "curiosity") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "inclines-toward") != null);
}

test "encodeEmotionalRegister emits axis names" {
    const allocator = std.testing.allocator;
    const axes = [_]v2.EmotionalAxis{
        .{ .name = "curiosity", .value = 0.82 },
        .{ .name = "warmth", .value = 0.55 },
    };
    const er: v2.EmotionalRegister = .{ .axes = &axes };
    const bytes = try encodeEmotionalRegister(allocator, er);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "curiosity") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "warmth") != null);
}
