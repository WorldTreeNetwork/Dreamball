//! Protocol v2 envelope encoders. See docs/PROTOCOL.md §12.
//!
//! All encoders produce deterministic dCBOR output matching the v1
//! canonical-ordering rules. The one documented exception is the
//! omnispherical-grid envelope, which uses floats — see §12.2.

const std = @import("std");
const Allocator = std.mem.Allocator;

const cbor = @import("cbor.zig");
const protocol = @import("protocol.zig");
const v2 = @import("protocol_v2.zig");
const envelope = @import("envelope.zig");
const Fingerprint = @import("fingerprint.zig").Fingerprint;

// ============================================================================
// jelly.guild (§12.1.6) — a typed DreamBall envelope with a guild payload
// attached as auxiliary assertions.
// ============================================================================

pub fn encodeGuild(
    allocator: Allocator,
    identity: [32]u8,
    genesis_hash: [32]u8,
    guild: v2.Guild,
    signatures: []const protocol.Signature,
) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();

    try w.writeTag(cbor.Tag.envelope);

    // Count assertions up front (members + admins + policy + signatures + guild-name + keyspace-root-hash).
    var assertion_count: u64 = 2; // guild-name, keyspace-root-hash
    if (guild.policy != null) assertion_count += 1;
    for (guild.members) |_| assertion_count += 1;
    for (guild.members) |m| if (m.is_admin) {
        assertion_count += 1;
    };
    for (signatures) |_| assertion_count += 1;

    try w.writeArrayHeader(1 + assertion_count);

    // Subject: tag 201 { type, format-version, identity, genesis-hash }
    try w.writeTag(cbor.Tag.leaf);
    try w.writeMapHeader(4);
    // dCBOR canonical ordering: sort keys by (len, lex)
    // "type"(4) < "identity"(8) < "genesis-hash"(12) < "format-version"(14)
    try w.writeText("type");
    try w.writeText("jelly.dreamball.guild");
    try w.writeText("identity");
    try w.writeBytes(&identity);
    try w.writeText("genesis-hash");
    try w.writeBytes(&genesis_hash);
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);

    // Assertions as [pred, obj] 2-arrays. Emit in sorted predicate order.
    // For determinism we emit: admin, member, policy, signed, guild-name, keyspace-root-hash.
    // dCBOR ordering over those predicate lengths: "admin"(5), "member"(6), "policy"(6),
    // "signed"(6), "guild-name"(10), "keyspace-root-hash"(18).
    for (guild.members) |m| if (m.is_admin) {
        try w.writeArrayHeader(2);
        try w.writeText("admin");
        try w.writeBytes(&m.member.bytes);
    };

    // members (all — admins are also listed under "member")
    for (guild.members) |m| {
        try w.writeArrayHeader(2);
        try w.writeText("member");
        try w.writeBytes(&m.member.bytes);
    }

    if (guild.policy) |p| {
        try w.writeArrayHeader(2);
        try w.writeText("policy");
        try writePolicy(&w, p);
    }

    for (signatures) |s| {
        try w.writeArrayHeader(2);
        try w.writeText("signed");
        try w.writeArrayHeader(2);
        try w.writeText(s.alg);
        try w.writeBytes(s.value);
    }

    try w.writeArrayHeader(2);
    try w.writeText("guild-name");
    try w.writeText(guild.guild_name);

    try w.writeArrayHeader(2);
    try w.writeText("keyspace-root-hash");
    try w.writeBytes(&guild.keyspace_root_hash);

    return w.toOwned();
}

fn writePolicy(w: *cbor.Writer, p: v2.GuildPolicy) !void {
    // Emit a simple map { "public": [...], "guild-only": [...], "admin-only": [...] }.
    // Keys sorted canonically: "public"(6), "admin-only"(10), "guild-only"(10).
    try w.writeTag(cbor.Tag.envelope);
    try w.writeTag(cbor.Tag.leaf);
    try w.writeMapHeader(5); // type, format-version, public, admin-only, guild-only
    try w.writeText("type");
    try w.writeText("jelly.guild-policy");
    try w.writeText("public");
    try w.writeArrayHeader(p.public.len);
    for (p.public) |s| try w.writeText(s);
    try w.writeText("admin-only");
    try w.writeArrayHeader(p.admin_only.len);
    for (p.admin_only) |s| try w.writeText(s);
    try w.writeText("guild-only");
    try w.writeArrayHeader(p.guild_only.len);
    for (p.guild_only) |s| try w.writeText(s);
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);
}

// ============================================================================
// jelly.dreamball.relic (§12.1.4) — a typed DreamBall that wraps a sealed
// inner envelope. Subject carries `sealed-payload-hash` + `unlock-guild`.
// ============================================================================

pub fn encodeRelic(
    allocator: Allocator,
    identity: [32]u8,
    genesis_hash: [32]u8,
    relic: v2.Relic,
    reveal_hint: ?[]const u8,
    signatures: []const protocol.Signature,
) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();

    try w.writeTag(cbor.Tag.envelope);

    var assertion_count: u64 = 0;
    if (reveal_hint != null) assertion_count += 1;
    if (relic.sealed_until != null) assertion_count += 1;
    for (signatures) |_| assertion_count += 1;

    try w.writeArrayHeader(1 + assertion_count);

    try w.writeTag(cbor.Tag.leaf);
    // Subject: type, format-version, identity, genesis-hash, sealed-payload-hash, unlock-guild.
    // Keys sorted canonically: "type"(4), "identity"(8), "unlock-guild"(12), "genesis-hash"(12),
    //   "format-version"(14), "sealed-payload-hash"(19).
    // For equal-length keys, lex order breaks ties.
    try w.writeMapHeader(6);
    try w.writeText("type");
    try w.writeText("jelly.dreamball.relic");
    try w.writeText("identity");
    try w.writeBytes(&identity);
    // "genesis-hash" < "unlock-guild" lex (g < u) so genesis first at len 12.
    try w.writeText("genesis-hash");
    try w.writeBytes(&genesis_hash);
    try w.writeText("unlock-guild");
    try w.writeBytes(&relic.unlock_guild.bytes);
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);
    try w.writeText("sealed-payload-hash");
    try w.writeBytes(&relic.sealed_payload_hash);

    if (reveal_hint) |hint| {
        try w.writeArrayHeader(2);
        try w.writeText("reveal-hint");
        try w.writeText(hint);
    }
    if (relic.sealed_until) |t| {
        try w.writeArrayHeader(2);
        try w.writeText("sealed-until");
        try w.writeTag(cbor.Tag.epoch_time);
        try w.writeUint(@intCast(t));
    }
    for (signatures) |s| {
        try w.writeArrayHeader(2);
        try w.writeText("signed");
        try w.writeArrayHeader(2);
        try w.writeText(s.alg);
        try w.writeBytes(s.value);
    }

    return w.toOwned();
}

// ============================================================================
// jelly.transmission (§12.9) — receipt of a Tool transfer.
// ============================================================================

pub fn encodeTransmission(
    allocator: Allocator,
    t: v2.Transmission,
) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();

    try w.writeTag(cbor.Tag.envelope);

    var assertion_count: u64 = 1; // tool-envelope
    if (t.sender_fp != null) assertion_count += 1;
    if (t.transmitted_at != null) assertion_count += 1;
    for (t.signatures) |_| assertion_count += 1;

    try w.writeArrayHeader(1 + assertion_count);

    try w.writeTag(cbor.Tag.leaf);
    // Subject keys: "type"(4), "tool-fp"(7), "target-fp"(9), "via-guild"(9),
    //   "format-version"(14).
    try w.writeMapHeader(5);
    try w.writeText("type");
    try w.writeText("jelly.transmission");
    try w.writeText("tool-fp");
    try w.writeBytes(&t.tool_fp.bytes);
    try w.writeText("target-fp");
    try w.writeBytes(&t.target_fp.bytes);
    try w.writeText("via-guild");
    try w.writeBytes(&t.via_guild.bytes);
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);

    // Assertions in sorted order: "sender-fp"(9), "signed"(6), "tool-envelope"(13), "transmitted-at"(14).
    // len-first ordering: "signed"(6) < "sender-fp"(9) < "tool-envelope"(13) < "transmitted-at"(14).
    for (t.signatures) |s| {
        try w.writeArrayHeader(2);
        try w.writeText("signed");
        try w.writeArrayHeader(2);
        try w.writeText(s.alg);
        try w.writeBytes(s.value);
    }
    if (t.sender_fp) |fp| {
        try w.writeArrayHeader(2);
        try w.writeText("sender-fp");
        try w.writeBytes(&fp.bytes);
    }
    try w.writeArrayHeader(2);
    try w.writeText("tool-envelope");
    // Inline the tool envelope bytes verbatim (already dCBOR).
    try w.appendSlice(t.tool_envelope);
    if (t.transmitted_at) |ts| {
        try w.writeArrayHeader(2);
        try w.writeText("transmitted-at");
        try w.writeTag(cbor.Tag.epoch_time);
        try w.writeUint(@intCast(ts));
    }

    return w.toOwned();
}

// ============================================================================
// Minimal encoders for memory / knowledge-graph / emotional-register /
// interaction-set. v2 MVP uses them as nested envelopes inside Agent DreamBalls;
// the renderer consumes them via the generated TS types.
// ============================================================================

pub fn encodeMemory(allocator: Allocator, m: v2.Memory) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();
    try w.writeTag(cbor.Tag.envelope);

    const attribute_count: u64 = m.nodes.len + m.connections.len + @as(u64, if (m.last_updated != null) 1 else 0);
    try w.writeArrayHeader(1 + attribute_count);

    try w.writeTag(cbor.Tag.leaf);
    try w.writeMapHeader(2);
    try w.writeText("type");
    try w.writeText("jelly.memory");
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);

    for (m.nodes) |n| {
        try w.writeArrayHeader(2);
        try w.writeText("node");
        try writeMemoryNode(&w, n);
    }
    for (m.connections) |c| {
        try w.writeArrayHeader(2);
        try w.writeText("connection");
        try writeMemoryConnection(&w, c);
    }
    if (m.last_updated) |t| {
        try w.writeArrayHeader(2);
        try w.writeText("last-updated");
        try w.writeTag(cbor.Tag.epoch_time);
        try w.writeUint(@intCast(t));
    }
    return w.toOwned();
}

fn writeMemoryNode(w: *cbor.Writer, n: v2.MemoryNode) !void {
    try w.writeTag(cbor.Tag.envelope);
    var assertion_count: u64 = 0;
    if (n.content != null) assertion_count += 1;
    assertion_count += n.lookups.len;
    if (n.created != null) assertion_count += 1;
    if (n.last_recalled != null) assertion_count += 1;
    try w.writeArrayHeader(1 + assertion_count);

    try w.writeTag(cbor.Tag.leaf);
    try w.writeMapHeader(3);
    try w.writeText("id");
    try w.writeUint(n.id);
    try w.writeText("type");
    try w.writeText("jelly.memory-node");
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);

    if (n.content) |c| {
        try w.writeArrayHeader(2);
        try w.writeText("content");
        try w.writeText(c);
    }
    for (n.lookups) |lk| {
        try w.writeArrayHeader(2);
        try w.writeText("lookup");
        try w.writeArrayHeader(2);
        try w.writeText(lk.name);
        // Float: use 64-bit for simplicity. The protocol spec allows
        // half/single floats; we use f64 as the widest canonical form.
        try writeF64(w, lk.value);
    }
    if (n.created) |t| {
        try w.writeArrayHeader(2);
        try w.writeText("created");
        try w.writeTag(cbor.Tag.epoch_time);
        try w.writeUint(@intCast(t));
    }
    if (n.last_recalled) |t| {
        try w.writeArrayHeader(2);
        try w.writeText("last-recalled");
        try w.writeTag(cbor.Tag.epoch_time);
        try w.writeUint(@intCast(t));
    }
}

fn writeMemoryConnection(w: *cbor.Writer, e: v2.MemoryConnection) !void {
    try w.writeTag(cbor.Tag.envelope);
    var attribute_count: u64 = 1; // strength
    if (e.label != null) attribute_count += 1;
    try w.writeArrayHeader(1 + attribute_count);

    try w.writeTag(cbor.Tag.leaf);
    // dCBOR canonical order: len ascending, then lex for equal lengths.
    // Keys: "to"(2), "from"(4), "kind"(4), "type"(4), "format-version"(14).
    // At length 4, lex order is "from" < "kind" < "type".
    try w.writeMapHeader(5);
    try w.writeText("to");
    try w.writeUint(e.to);
    try w.writeText("from");
    try w.writeUint(e.from);
    try w.writeText("kind");
    try w.writeText(e.kind.toWireString());
    try w.writeText("type");
    try w.writeText("jelly.memory-connection");
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);

    try w.writeArrayHeader(2);
    try w.writeText("strength");
    try writeF64(w, e.strength);
    if (e.label) |lbl| {
        try w.writeArrayHeader(2);
        try w.writeText("label");
        try w.writeText(lbl);
    }
}

pub fn encodeKnowledgeGraph(allocator: Allocator, kg: v2.KnowledgeGraph) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();
    try w.writeTag(cbor.Tag.envelope);

    var ac: u64 = kg.triples.len;
    if (kg.source != null) ac += 1;
    try w.writeArrayHeader(1 + ac);

    try w.writeTag(cbor.Tag.leaf);
    try w.writeMapHeader(2);
    try w.writeText("type");
    try w.writeText("jelly.knowledge-graph");
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);

    for (kg.triples) |t| {
        try w.writeArrayHeader(2);
        try w.writeText("triple");
        try w.writeArrayHeader(3);
        try w.writeText(t.from);
        try w.writeText(t.label);
        try w.writeText(t.to);
    }
    if (kg.source) |s| {
        try w.writeArrayHeader(2);
        try w.writeText("source");
        try w.writeText(s);
    }
    return w.toOwned();
}

pub fn encodeEmotionalRegister(allocator: Allocator, er: v2.EmotionalRegister) ![]u8 {
    var w = cbor.Writer.init(allocator);
    errdefer w.deinit();
    try w.writeTag(cbor.Tag.envelope);

    var ac: u64 = er.axes.len;
    if (er.observed_at != null) ac += 1;
    try w.writeArrayHeader(1 + ac);

    try w.writeTag(cbor.Tag.leaf);
    try w.writeMapHeader(2);
    try w.writeText("type");
    try w.writeText("jelly.emotional-register");
    try w.writeText("format-version");
    try w.writeUint(protocol.FORMAT_VERSION_V2);

    for (er.axes) |ax| {
        try w.writeArrayHeader(2);
        try w.writeText("axis");
        try w.writeMapHeader(4);
        try w.writeText("max");
        try writeF64(&w, ax.max);
        try w.writeText("min");
        try writeF64(&w, ax.min);
        try w.writeText("name");
        try w.writeText(ax.name);
        try w.writeText("value");
        try writeF64(&w, ax.value);
    }
    if (er.observed_at) |t| {
        try w.writeArrayHeader(2);
        try w.writeText("observed-at");
        try w.writeTag(cbor.Tag.epoch_time);
        try w.writeUint(@intCast(t));
    }
    return w.toOwned();
}

// ============================================================================
// Float helper — the one documented floats-allowed corner of the protocol.
// Uses IEEE 754 f64 (CBOR major type 7, additional info 27).
// ============================================================================

fn writeF64(w: *cbor.Writer, v: f64) !void {
    // Major type 7, additional info 27 = float64.
    const tag_byte: u8 = (7 << 5) | 27;
    try w.buf.append(w.allocator, tag_byte);
    var buf: [8]u8 = undefined;
    const bits: u64 = @bitCast(v);
    std.mem.writeInt(u64, &buf, bits, .big);
    try w.buf.appendSlice(w.allocator, &buf);
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
    const bytes = try encodeRelic(allocator, [_]u8{1} ** 32, [_]u8{2} ** 32, relic, relic.reveal_hint, &.{});
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Look behind the mirror") != null);
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
