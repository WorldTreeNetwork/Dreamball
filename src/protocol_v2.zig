//! Protocol v2 auxiliary envelope types. See docs/PROTOCOL.md §12.
//!
//! Kept in its own module so the v1 DreamBall surface in `protocol.zig`
//! stays compact. Everything here is ADDITIVE — v1 consumers that ignore
//! these types continue to work on v1 envelopes.

const std = @import("std");
const Allocator = std.mem.Allocator;

const protocol = @import("protocol.zig");
const Fingerprint = @import("fingerprint.zig").Fingerprint;

// ============================================================================
// §12.2 jelly.omnispherical-grid
// ============================================================================

pub const Vec3 = struct { x: f64, y: f64, z: f64 };

pub const CameraRing = struct {
    radius: f64,
    tilt: f64,
    fov: f64,
};

pub const OmnisphericalGrid = struct {
    pole_north: Vec3 = .{ .x = 0, .y = 1, .z = 0 },
    pole_south: Vec3 = .{ .x = 0, .y = -1, .z = 0 },
    camera_rings: []const CameraRing = &.{},
    layer_depth: u32 = 3,
    /// Subdivision level — forward-only (see docs/VISION.md §4.4.5).
    resolution: u32 = 8,
    note: ?[]const u8 = null,
};

// ============================================================================
// §12.3 jelly.memory
// ============================================================================

pub const MemoryConnectionKind = enum {
    semantic,
    emotional,
    temporal,
    other,

    pub fn toWireString(self: MemoryConnectionKind) []const u8 {
        return switch (self) {
            .semantic => "semantic",
            .emotional => "emotional",
            .temporal => "temporal",
            .other => "other",
        };
    }
};

pub const MemoryNode = struct {
    id: u64,
    /// Inline content (text) OR an asset fingerprint reference — one must be set.
    content: ?[]const u8 = null,
    /// Lookups: name → sort-key value. Supports named indices like an
    /// "emotional" lookup that sorts memory by emotional salience.
    lookups: []const LookupEntry = &.{},
    created: ?i64 = null,
    last_recalled: ?i64 = null,

    pub const LookupEntry = struct {
        name: []const u8,
        value: f64,
    };
};

pub const MemoryConnection = struct {
    from: u64,
    to: u64,
    kind: MemoryConnectionKind,
    strength: f64 = 1.0,
    label: ?[]const u8 = null,
};

pub const Memory = struct {
    nodes: []const MemoryNode = &.{},
    connections: []const MemoryConnection = &.{},
    last_updated: ?i64 = null,
};

// ============================================================================
// §12.4 jelly.knowledge-graph
// ============================================================================

pub const Triple = struct {
    from: []const u8,
    label: []const u8,
    /// Either a text value or a fingerprint reference to another DreamBall.
    to: []const u8,
};

pub const KnowledgeGraph = struct {
    triples: []const Triple = &.{},
    source: ?[]const u8 = null,
};

// ============================================================================
// §12.5 jelly.emotional-register
// ============================================================================

pub const EmotionalAxis = struct {
    name: []const u8,
    value: f64,
    min: f64 = 0.0,
    max: f64 = 1.0,
};

pub const EmotionalRegister = struct {
    axes: []const EmotionalAxis = &.{},
    observed_at: ?i64 = null,
};

// ============================================================================
// §12.6 jelly.interaction-set
// ============================================================================

pub const InteractionKind = enum { speak, listen, act, receive };

pub const Interaction = struct {
    turn: u32,
    actor: Fingerprint,
    kind: InteractionKind,
    content: ?[]const u8 = null,
    timestamp: ?i64 = null,
    outcome: ?[]const u8 = null,

    pub fn kindString(self: Interaction) []const u8 {
        return switch (self.kind) {
            .speak => "speak",
            .listen => "listen",
            .act => "act",
            .receive => "receive",
        };
    }
};

pub const InteractionSet = struct {
    /// Content-addressable id for the set (16 random bytes at creation time).
    set_id: [16]u8,
    interactions: []const Interaction = &.{},
    created: ?i64 = null,
};

// ============================================================================
// §12.7 jelly.guild-policy
// ============================================================================

pub const GuildPolicy = struct {
    public: []const []const u8 = &.{ "look", "thumbnail" },
    guild_only: []const []const u8 = &.{
        "memory",
        "knowledge-graph",
        "emotional-register",
        "interaction-set",
    },
    admin_only: []const []const u8 = &.{"secret"},
    note: ?[]const u8 = null,
};

// ============================================================================
// §12.8 jelly.secret-ref
// ============================================================================

pub const SecretRef = struct {
    name: []const u8,
    /// Opaque locator string (e.g. `recrypt://…`). For v2 this is mocked
    /// — see TODO-CRYPTO markers in signer.zig and the renderer backend.
    locator: []const u8,
    issued_by: ?Fingerprint = null,
    description: ?[]const u8 = null,
};

// ============================================================================
// §12.9 jelly.transmission
// ============================================================================

pub const Transmission = struct {
    tool_fp: Fingerprint,
    target_fp: Fingerprint,
    via_guild: Fingerprint,
    sender_fp: ?Fingerprint = null,
    transmitted_at: ?i64 = null,
    /// The Tool envelope bytes inlined into the transmission receipt.
    tool_envelope: []const u8 = &.{},
    signatures: []const protocol.Signature = &.{},
};

// ============================================================================
// §12.1 Guild type-specific data
// ============================================================================

pub const GuildMembership = struct {
    member: Fingerprint,
    is_admin: bool = false,
};

pub const Guild = struct {
    /// Human-readable name for display.
    guild_name: []const u8,
    /// Blake3 of the keyspace root — the Guild's fingerprint.
    keyspace_root_hash: [32]u8,
    members: []const GuildMembership = &.{},
    policy: ?GuildPolicy = null,
};

// ============================================================================
// §12.1.4 Relic type-specific data
// ============================================================================

pub const Relic = struct {
    /// Blake3 of the sealed inner envelope bytes.
    sealed_payload_hash: [32]u8,
    /// Guild fingerprint authorised to unlock this relic.
    unlock_guild: Fingerprint,
    reveal_hint: ?[]const u8 = null,
    sealed_until: ?i64 = null,
};

// ============================================================================
// Tests — sanity-check the value types round-trip through Zig defaults
// ============================================================================

test "DreamBallType wire strings round-trip" {
    const types = [_]protocol.DreamBallType{ .avatar, .agent, .tool, .relic, .field, .guild };
    for (types) |t| {
        const s = t.toWireString();
        const got = protocol.DreamBallType.fromWireString(s) orelse unreachable;
        try std.testing.expectEqual(t, got);
    }
}

test "DreamBallType short tags round-trip" {
    const types = [_]protocol.DreamBallType{ .avatar, .agent, .tool, .relic, .field, .guild };
    for (types) |t| {
        const tg = t.tag();
        const got = protocol.DreamBallType.fromTag(tg) orelse unreachable;
        try std.testing.expectEqual(t, got);
    }
}

test "Guild default policy has sensible slot split" {
    const p: GuildPolicy = .{};
    // look and memory must be in different buckets.
    var look_public = false;
    for (p.public) |s| if (std.mem.eql(u8, s, "look")) {
        look_public = true;
    };
    try std.testing.expect(look_public);
    var mem_guild = false;
    for (p.guild_only) |s| if (std.mem.eql(u8, s, "memory")) {
        mem_guild = true;
    };
    try std.testing.expect(mem_guild);
    var secret_admin = false;
    for (p.admin_only) |s| if (std.mem.eql(u8, s, "secret")) {
        secret_admin = true;
    };
    try std.testing.expect(secret_admin);
}

test "MemoryConnectionKind strings" {
    try std.testing.expectEqualStrings("semantic", MemoryConnectionKind.semantic.toWireString());
    try std.testing.expectEqualStrings("emotional", MemoryConnectionKind.emotional.toWireString());
}

test "Interaction kind string" {
    const it: Interaction = .{
        .turn = 0,
        .actor = .{ .bytes = [_]u8{0} ** 32 },
        .kind = .speak,
    };
    try std.testing.expectEqualStrings("speak", it.kindString());
}
