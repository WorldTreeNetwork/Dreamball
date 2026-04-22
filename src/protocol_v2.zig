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
    /// Sender's Ed25519 public key, embedded in the core so the receipt
    /// is self-verifying without a pubkey-bundle lookup. When set, the
    /// envelope bumps to `format-version: 3`. See PROTOCOL.md §12.9.
    sender_identity: ?[32]u8 = null,
    /// Sender's ML-DSA-87 public key. Requires `sender_identity` to be
    /// set as well. When present the envelope is `format-version: 3`.
    sender_identity_pq: ?[protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8 = null,
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
// §13.1 field-kind attribute on jelly.dreamball.field
// ============================================================================

/// Optional `field-kind` attribute on a `jelly.dreamball.field` envelope.
/// Attribute-level addition — does NOT bump `format-version`.
/// Unknown values MUST be preserved verbatim (open-enum rule, §13.1).
pub const FieldKind = struct {
    /// Wire name: "field-kind".
    /// Values: "palace" | "room" | "ambient" | <open-enum>
    value: []const u8,

    pub const palace = "palace";
    pub const room = "room";
    pub const ambient = "ambient";
};

// ============================================================================
// §13.2 jelly.layout
// ============================================================================

/// A quaternion rotation.
pub const Quaternion = struct {
    qx: f32,
    qy: f32,
    qz: f32,
    qw: f32,
};

/// One child placement inside a layout.
pub const Placement = struct {
    /// Blake3 fingerprint of the child DreamBall.
    child_fp: [32]u8,
    /// Position in the parent's local coordinate frame.
    position: [3]f32,
    /// Orientation as a quaternion.
    facing: Quaternion,
};

pub const Layout = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"jelly.layout"`.
    pub const type_string: []const u8 = "jelly.layout";

    placements: []const Placement = &.{},
    note: ?[]const u8 = null,
};

// ============================================================================
// §13.3 jelly.timeline + jelly.action
// ============================================================================

/// RC2 — ActionKind enum with all 9 known kinds.
/// Wire representation is the kebab-case string in comments.
pub const ActionKind = enum {
    palace_minted, // "palace-minted"
    room_added, // "room-added"
    avatar_inscribed, // "avatar-inscribed"
    aqueduct_created, // "aqueduct-created"
    move, // "move"
    true_naming, // "true-naming"
    inscription_updated, // "inscription-updated"
    inscription_orphaned, // "inscription-orphaned"
    inscription_pending_embedding, // "inscription-pending-embedding"

    pub fn toWireString(self: ActionKind) []const u8 {
        return switch (self) {
            .palace_minted => "palace-minted",
            .room_added => "room-added",
            .avatar_inscribed => "avatar-inscribed",
            .aqueduct_created => "aqueduct-created",
            .move => "move",
            .true_naming => "true-naming",
            .inscription_updated => "inscription-updated",
            .inscription_orphaned => "inscription-orphaned",
            .inscription_pending_embedding => "inscription-pending-embedding",
        };
    }
};

pub const Timeline = struct {
    pub const format_version: u32 = 3;
    /// Wire type string: `"jelly.timeline"`.
    pub const type_string: []const u8 = "jelly.timeline";

    /// 1:1 identity anchor — which palace this timeline belongs to.
    palace_fp: [32]u8,
    /// Set of Blake3 hashes of current leaf actions; cardinality >= 1.
    head_hashes: [][32]u8,
    /// Ordered action envelopes (stored inline; encoders handle them separately).
    /// This field is a placeholder for the struct shape — encoder in Story 1.3.
    note: ?[]const u8 = null,
};

/// A `jelly.action-ref` is a 32-byte Blake3 of a canonical `jelly.action` envelope.
pub const ActionRef = [32]u8;

pub const Action = struct {
    pub const format_version: u32 = 3;
    /// Wire type string: `"jelly.action"`.
    pub const type_string: []const u8 = "jelly.action";

    action_kind: ActionKind,
    /// ACKS — previous head(s) this action acknowledges; one for linear, multiple for merges.
    parent_hashes: [][32]u8,
    /// Fingerprint of the signer.
    actor: [32]u8,
    /// Optional target DreamBall fingerprint.
    target_fp: ?[32]u8 = null,
    /// Unix timestamp (seconds).
    timestamp: ?i64 = null,
    /// Optional logical dependencies (disjoint from parent_hashes).
    deps: []const ActionRef = &.{},
    /// Optional invalidated prior actions.
    nacks: []const ActionRef = &.{},
};

// ============================================================================
// §13.4 jelly.aqueduct
// ============================================================================

pub const AqueductPhase = enum {
    in,
    out,
    standing,
    resonant,

    pub fn toWireString(self: AqueductPhase) []const u8 {
        return switch (self) {
            .in => "in",
            .out => "out",
            .standing => "standing",
            .resonant => "resonant",
        };
    }
};

pub const Aqueduct = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"jelly.aqueduct"`.
    pub const type_string: []const u8 = "jelly.aqueduct";

    from: [32]u8,
    to: [32]u8,
    /// Open-enum kind; use wire strings like "gaze", "visit", "transmit", etc.
    kind: []const u8,

    capacity: f32 = 0.0,
    strength: f32 = 0.0,
    resistance: f32 = 0.0,
    capacitance: f32 = 0.0,
    /// Snapshot accumulator — not load-bearing, MAY be absent (TC16).
    conductance: ?f32 = null,
    phase: ?AqueductPhase = null,
    last_traversed: ?i64 = null,
};

// ============================================================================
// §13.5 jelly.element-tag
// ============================================================================

pub const ElementTag = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"jelly.element-tag"`.
    pub const type_string: []const u8 = "jelly.element-tag";

    /// Open-enum element value; e.g. "wood", "fire", "earth", "metal", "water", …
    element: []const u8,
    /// Optional qualifier; e.g. "nourishing", "destruction", "yin", "yang", …
    phase: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

// ============================================================================
// §13.6 jelly.trust-observation
// ============================================================================

pub const TrustAxis = struct {
    name: []const u8,
    value: f64,
    range: [2]f64 = .{ 0.0, 1.0 },
};

pub const TrustObservation = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"jelly.trust-observation"`.
    pub const type_string: []const u8 = "jelly.trust-observation";

    /// Fingerprint of the signer/observer.
    observer: [32]u8,
    /// Fingerprint of the party being observed.
    about: [32]u8,

    axes: []const TrustAxis = &.{},
    observed_at: ?i64 = null,
    context: ?[]const u8 = null,
    signatures: []const protocol.Signature = &.{},
};

// ============================================================================
// §13.7 jelly.inscription
// ============================================================================

pub const Inscription = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"jelly.inscription"`.
    pub const type_string: []const u8 = "jelly.inscription";

    /// Open-enum surface; e.g. "scroll", "tablet", "book-spread", "etched-wall", "floating-glyph", …
    surface: []const u8,
    /// "auto" = renderer chooses; "curator" = parent room's jelly.layout.
    placement: []const u8 = "auto",
    note: ?[]const u8 = null,
};

// ============================================================================
// §13.8 jelly.mythos
// ============================================================================

pub const Mythos = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"jelly.mythos"`.
    pub const type_string: []const u8 = "jelly.mythos";

    /// true iff this is the first mythos of this chain.
    is_genesis: bool,
    /// Blake3 of the prior jelly.mythos envelope; MUST be absent iff is_genesis is true.
    predecessor: ?[32]u8 = null,

    /// POETIC ONLY — fingerprint of the DreamBall this mythos is about.
    about: ?[32]u8 = null,
    /// Open-enum form; e.g. "blurb", "invocation", "image", "utterance", "glyph", "true-name", …
    form: ?[]const u8 = null,
    /// The mythos in full poetic form.
    body: ?[]const u8 = null,
    /// Optional condensed totem.
    true_name: ?[]const u8 = null,
    /// CANONICAL ONLY — paired 'true-naming' action ref on the palace timeline.
    discovered_in: ?ActionRef = null,
    /// CANONICAL ONLY — poetic mythoi that informed this renaming.
    synthesizes: [][32]u8 = &.{},
    /// POETIC ONLY — other mythoi this author was thinking with.
    inspired_by: [][32]u8 = &.{},

    author: ?[32]u8 = null,
    authored_at: ?i64 = null,
};

// ============================================================================
// §13.9 jelly.archiform
// ============================================================================

pub const Archiform = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"jelly.archiform"`.
    pub const type_string: []const u8 = "jelly.archiform";

    /// Open-enum form; e.g. "library", "forge", "throne-room", …
    form: []const u8,
    /// Optional lineage; e.g. "hermetic", "shinto", "vedic", "computational", "none", …
    tradition: ?[]const u8 = null,
    /// Optional parent archiform this one specialises.
    parent_form: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

// ============================================================================
// §13.11 palace invariant primitive (AC4)
// ============================================================================

pub const PalaceInvariantError = error{
    /// PROTOCOL.md §13.11 fixture 1: a Field with field-kind "palace" MUST carry
    /// a jelly.mythos attribute. This error is returned when that invariant is
    /// violated. Full enforcement lives in Epic 3 (`jelly verify`).
    PalaceMissingMythos,
};

/// Checks the palace-root invariant from PROTOCOL.md §13.11 fixture 1:
/// a Field tagged `field-kind: "palace"` MUST carry a `jelly.mythos` attribute.
/// `has_mythos` should be set to true if the envelope carries any `jelly.mythos` attribute.
pub fn palaceInvariants(field_kind: ?[]const u8, has_mythos: bool) PalaceInvariantError!void {
    if (field_kind) |fk| {
        if (std.mem.eql(u8, fk, FieldKind.palace) and !has_mythos) {
            return error.PalaceMissingMythos;
        }
    }
}

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

// ============================================================================
// Story 1.2 — palace envelope struct-shape tests
// ============================================================================

test "struct shape: Layout" {
    const l: Layout = .{};
    try std.testing.expectEqual(@as(u32, 2), Layout.format_version);
    try std.testing.expectEqualStrings("jelly.layout", Layout.type_string);
    try std.testing.expectEqual(@as(usize, 0), l.placements.len);
    try std.testing.expectEqual(@as(?[]const u8, null), l.note);
}

test "struct shape: Timeline" {
    var heads = [_][32]u8{[_]u8{0xAB} ** 32};
    const t: Timeline = .{
        .palace_fp = [_]u8{0x01} ** 32,
        .head_hashes = &heads,
    };
    try std.testing.expectEqual(@as(u32, 3), Timeline.format_version);
    try std.testing.expectEqualStrings("jelly.timeline", Timeline.type_string);
    try std.testing.expectEqual(@as(usize, 1), t.head_hashes.len);
    try std.testing.expectEqual(@as(u8, 0xAB), t.head_hashes[0][0]);
}

test "struct shape: Action" {
    var parents = [_][32]u8{[_]u8{0x02} ** 32};
    const a: Action = .{
        .action_kind = .true_naming,
        .parent_hashes = &parents,
        .actor = [_]u8{0x03} ** 32,
    };
    try std.testing.expectEqual(@as(u32, 3), Action.format_version);
    try std.testing.expectEqualStrings("jelly.action", Action.type_string);
    try std.testing.expectEqualStrings("true-naming", a.action_kind.toWireString());
    try std.testing.expectEqual(@as(usize, 0), a.deps.len);
    try std.testing.expectEqual(@as(usize, 0), a.nacks.len);
}

test "struct shape: Aqueduct" {
    const aq: Aqueduct = .{
        .from = [_]u8{0x04} ** 32,
        .to = [_]u8{0x05} ** 32,
        .kind = "gaze",
    };
    try std.testing.expectEqual(@as(u32, 2), Aqueduct.format_version);
    try std.testing.expectEqualStrings("jelly.aqueduct", Aqueduct.type_string);
    try std.testing.expectEqual(@as(?f32, null), aq.conductance);
    try std.testing.expectEqual(@as(?AqueductPhase, null), aq.phase);
}

test "struct shape: ElementTag" {
    const et: ElementTag = .{ .element = "wood" };
    try std.testing.expectEqual(@as(u32, 2), ElementTag.format_version);
    try std.testing.expectEqualStrings("jelly.element-tag", ElementTag.type_string);
    try std.testing.expectEqualStrings("wood", et.element);
    try std.testing.expectEqual(@as(?[]const u8, null), et.phase);
}

test "struct shape: TrustObservation" {
    const to: TrustObservation = .{
        .observer = [_]u8{0x06} ** 32,
        .about = [_]u8{0x07} ** 32,
    };
    try std.testing.expectEqual(@as(u32, 2), TrustObservation.format_version);
    try std.testing.expectEqualStrings("jelly.trust-observation", TrustObservation.type_string);
    try std.testing.expectEqual(@as(usize, 0), to.axes.len);
    try std.testing.expectEqual(@as(usize, 0), to.signatures.len);
}

test "struct shape: Inscription" {
    const ins: Inscription = .{ .surface = "scroll" };
    try std.testing.expectEqual(@as(u32, 2), Inscription.format_version);
    try std.testing.expectEqualStrings("jelly.inscription", Inscription.type_string);
    try std.testing.expectEqualStrings("scroll", ins.surface);
    try std.testing.expectEqualStrings("auto", ins.placement);
}

test "struct shape: Mythos" {
    const m: Mythos = .{ .is_genesis = true };
    try std.testing.expectEqual(@as(u32, 2), Mythos.format_version);
    try std.testing.expectEqualStrings("jelly.mythos", Mythos.type_string);
    try std.testing.expect(m.is_genesis);
    try std.testing.expectEqual(@as(?[32]u8, null), m.predecessor);
    try std.testing.expectEqual(@as(?[32]u8, null), m.about);
}

test "struct shape: Archiform" {
    const ar: Archiform = .{ .form = "library" };
    try std.testing.expectEqual(@as(u32, 2), Archiform.format_version);
    try std.testing.expectEqualStrings("jelly.archiform", Archiform.type_string);
    try std.testing.expectEqualStrings("library", ar.form);
    try std.testing.expectEqual(@as(?[]const u8, null), ar.parent_form);
}

test "AC2: field-kind palace and room preserved" {
    const palace_fk: FieldKind = .{ .value = FieldKind.palace };
    const room_fk: FieldKind = .{ .value = FieldKind.room };
    try std.testing.expectEqualStrings("palace", palace_fk.value);
    try std.testing.expectEqualStrings("room", room_fk.value);
}

test "AC3: unknown field-kind preserved verbatim (open-enum)" {
    const sanctuary_fk: FieldKind = .{ .value = "sanctuary" };
    try std.testing.expectEqualStrings("sanctuary", sanctuary_fk.value);
}

test "AC4: palaceInvariants returns PalaceMissingMythos for palace without mythos" {
    const result = palaceInvariants("palace", false);
    try std.testing.expectError(error.PalaceMissingMythos, result);
    // palace with mythos is ok
    try palaceInvariants("palace", true);
    // non-palace field kind without mythos is ok
    try palaceInvariants("room", false);
    try palaceInvariants(null, false);
}

test "ActionKind: all 9 wire strings present" {
    try std.testing.expectEqualStrings("palace-minted", ActionKind.palace_minted.toWireString());
    try std.testing.expectEqualStrings("room-added", ActionKind.room_added.toWireString());
    try std.testing.expectEqualStrings("avatar-inscribed", ActionKind.avatar_inscribed.toWireString());
    try std.testing.expectEqualStrings("aqueduct-created", ActionKind.aqueduct_created.toWireString());
    try std.testing.expectEqualStrings("move", ActionKind.move.toWireString());
    try std.testing.expectEqualStrings("true-naming", ActionKind.true_naming.toWireString());
    try std.testing.expectEqualStrings("inscription-updated", ActionKind.inscription_updated.toWireString());
    try std.testing.expectEqualStrings("inscription-orphaned", ActionKind.inscription_orphaned.toWireString());
    try std.testing.expectEqualStrings("inscription-pending-embedding", ActionKind.inscription_pending_embedding.toWireString());
}
