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
// §12.2 ball.omnispherical-grid
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
// §12.3 ball.memory
// ============================================================================

// The memory slot is now a first-class DreamBall slot living in protocol.zig
// beside look/feel/act (see docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md).
// Dreamball-h7s.1 removed the `v2.Memory` / `v2.MemoryNode` / etc. re-export
// shims below (no callers referenced them outside this file) — use
// `protocol.Memory` / `protocol.MemoryNode` / etc. directly.

// ============================================================================
// §12.4 ball.knowledge-graph / §12.5 ball.emotional-register /
// §12.6 ball.interaction-set / §12.7 ball.guild-policy
// ============================================================================

// These four slots are now first-class DreamBall slots living in protocol.zig
// beside look/feel/act/memory (see
// docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md, Zig is
// canonical). Dreamball-h7s.1 removed the `v2.KnowledgeGraph` / `v2.Triple` /
// `v2.EmotionalAxis` / `v2.Interaction` / etc. re-export shims (no external
// callers) — use `protocol.KnowledgeGraph` / `protocol.Triple` / etc. directly.
// `GuildPolicy` is kept: `envelope_v2.zig:writePolicy` still takes `v2.GuildPolicy`.
pub const GuildPolicy = protocol.GuildPolicy;

// ============================================================================
// §12.8 ball.secret-ref
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
// §12.9 ball.transmission
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
// §13.1 field-kind attribute on ball.dreamball.field
// ============================================================================

// Dreamball-h7s.1: the `FieldKind` struct (wire attribute `field-kind` on
// `ball.dreamball.field`, §13.1) was removed — it wrapped a single
// `[]const u8` and had zero callers outside its own tests; `DreamBall.field_kind`
// is already `?[]const u8` at protocol.zig:334. The wire attribute itself is
// untouched; only the redundant Zig wrapper type is gone.

// ============================================================================
// §13.2 ball.layout
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
    /// Wire type string: `"ball.layout"`.
    pub const type_string: []const u8 = "ball.layout";

    placements: []const Placement = &.{},
    note: ?[]const u8 = null,
};

// ============================================================================
// §13.3 ball.timeline + ball.action
// ============================================================================

/// Palace-profile kind palette — the conventional `kind` strings the palace
/// authors use on `ball.action`. As of v4 (D-037) the wire type carries an
/// OPEN `kind: []const u8`, so this enum is a convenience/profile helper, NOT
/// the wire field: it maps the 9 known palace verbs to their canonical wire
/// strings via `toWireString()`. Other consumers author arbitrary `kind`
/// strings (D-038 dot-namespace convention) without touching this enum.
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
    /// Wire type string: `"ball.timeline"`.
    pub const type_string: []const u8 = "ball.timeline";

    /// 1:1 identity anchor — which palace this timeline belongs to.
    palace_fp: [32]u8,
    /// Set of Blake3 hashes of current leaf actions; cardinality >= 1.
    head_hashes: [][32]u8,
    /// Ordered action envelopes (stored inline; encoders handle them separately).
    /// This field is a placeholder for the struct shape — encoder in Story 1.3.
    note: ?[]const u8 = null,
};

/// A `ball.action-ref` is a 32-byte Blake3 of a canonical `ball.action` envelope.
pub const ActionRef = [32]u8;

pub const Action = struct {
    pub const format_version: u32 = 4;
    /// Wire type string: `"ball.action"`.
    pub const type_string: []const u8 = "ball.action";

    /// OPEN kind string (D-037/D-038). Replaces the closed `action_kind` enum
    /// of v3. Palace authors set this via `ActionKind.x.toWireString()`; other
    /// consumers supply their own dot-namespaced verb. Wire key is `"kind"`.
    kind: []const u8,
    /// ACKS — previous head(s) this action acknowledges; one for linear, multiple for merges.
    parent_hashes: [][32]u8,
    /// Fingerprint of the signer.
    actor: [32]u8,
    /// Opaque, consumer-defined CBOR payload carried as a CBOR byte string
    /// (CBOR-in-CBOR, D-040/D-043). The protocol does not interpret its schema.
    body: ?[]const u8 = null,
    /// Hybrid Logical Clock `[l, c]` (D-039): index 0 = `l` (ms wall-clock),
    /// index 1 = `c` (intra-`l` counter). Structural in v4 envelopes.
    hlc: [2]u64,
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
// §13.4 ball.aqueduct
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
    /// Wire type string: `"ball.aqueduct"`.
    pub const type_string: []const u8 = "ball.aqueduct";

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
// §13.5 ball.element-tag
// ============================================================================

pub const ElementTag = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"ball.element-tag"`.
    pub const type_string: []const u8 = "ball.element-tag";

    /// Open-enum element value; e.g. "wood", "fire", "earth", "metal", "water", …
    element: []const u8,
    /// Optional qualifier; e.g. "nourishing", "destruction", "yin", "yang", …
    phase: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

// ============================================================================
// §13.6 ball.trust-observation
// ============================================================================

pub const TrustAxis = struct {
    name: []const u8,
    value: f64,
    range: [2]f64 = .{ 0.0, 1.0 },
};

pub const TrustObservation = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"ball.trust-observation"`.
    pub const type_string: []const u8 = "ball.trust-observation";

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
// §13.7 ball.inscription
// ============================================================================

pub const Inscription = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"ball.inscription"`.
    pub const type_string: []const u8 = "ball.inscription";

    /// Open-enum surface; e.g. "scroll", "tablet", "book-spread", "etched-wall", "floating-glyph", …
    surface: []const u8,
    /// "auto" = renderer chooses; "curator" = parent room's ball.layout.
    placement: []const u8 = "auto",
    note: ?[]const u8 = null,
};

// ============================================================================
// §13.8 ball.mythos
// ============================================================================

pub const Mythos = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"ball.mythos"`.
    pub const type_string: []const u8 = "ball.mythos";

    /// true iff this is the first mythos of this chain.
    is_genesis: bool,
    /// Blake3 of the prior ball.mythos envelope; MUST be absent iff is_genesis is true.
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
// §13.9 ball.archiform
// ============================================================================

pub const Archiform = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"ball.archiform"`.
    pub const type_string: []const u8 = "ball.archiform";

    /// Open-enum form; e.g. "library", "forge", "throne-room", …
    form: []const u8,
    /// Optional lineage; e.g. "hermetic", "shinto", "vedic", "computational", "none", …
    tradition: ?[]const u8 = null,
    /// Optional parent archiform this one specialises.
    parent_form: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

// Dreamball-h7s.1: `Object3d` (§13.10 `ball.object3d`) was removed — its
// docstring said it exists to demonstrate the Zig-canonical authoring
// pipeline, which the 2026-08-06 Rust-canonical ADR dissolved. Its golden
// fixture is PRESERVED as data: `golden.GOLDEN_OBJECT3D_BYTES_HEX` /
// `GOLDEN_OBJECT3D_BLAKE3` in src/golden.zig are untouched, and
// `tools/export-golden-fixtures/main.zig` now writes the `object3d` manifest
// entry by decoding those pinned bytes directly instead of re-deriving them
// from a live `Object3d{}` + `encodeObject3d` call (also removed, from
// envelope_v2.zig). `fixtures/goldens/manifest.json`'s `object3d` entry is
// therefore byte-for-byte unchanged. See the deletion report on
// Dreamball-h7s.1 for the full accounting.

// Dreamball-h7s.1: `palaceInvariants` + `PalaceInvariantError` (§13.11) were
// removed — a function named after one application (the palace CLI) had no
// business living in the protocol core, and it had zero callers outside its
// own test.

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
    try std.testing.expectEqualStrings("semantic", protocol.MemoryConnectionKind.semantic.toWireString());
    try std.testing.expectEqualStrings("emotional", protocol.MemoryConnectionKind.emotional.toWireString());
}

test "Interaction kind string" {
    const it: protocol.Interaction = .{
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
    try std.testing.expectEqualStrings("ball.layout", Layout.type_string);
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
    try std.testing.expectEqualStrings("ball.timeline", Timeline.type_string);
    try std.testing.expectEqual(@as(usize, 1), t.head_hashes.len);
    try std.testing.expectEqual(@as(u8, 0xAB), t.head_hashes[0][0]);
}

test "struct shape: Action" {
    var parents = [_][32]u8{[_]u8{0x02} ** 32};
    const a: Action = .{
        .kind = ActionKind.true_naming.toWireString(),
        .parent_hashes = &parents,
        .actor = [_]u8{0x03} ** 32,
        .hlc = .{ 0, 0 },
    };
    try std.testing.expectEqual(@as(u32, 4), Action.format_version);
    try std.testing.expectEqualStrings("ball.action", Action.type_string);
    try std.testing.expectEqualStrings("true-naming", a.kind);
    try std.testing.expectEqual(@as(?[]const u8, null), a.body);
    try std.testing.expectEqual(@as(u64, 0), a.hlc[1]);
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
    try std.testing.expectEqualStrings("ball.aqueduct", Aqueduct.type_string);
    try std.testing.expectEqual(@as(?f32, null), aq.conductance);
    try std.testing.expectEqual(@as(?AqueductPhase, null), aq.phase);
}

test "struct shape: ElementTag" {
    const et: ElementTag = .{ .element = "wood" };
    try std.testing.expectEqual(@as(u32, 2), ElementTag.format_version);
    try std.testing.expectEqualStrings("ball.element-tag", ElementTag.type_string);
    try std.testing.expectEqualStrings("wood", et.element);
    try std.testing.expectEqual(@as(?[]const u8, null), et.phase);
}

test "struct shape: TrustObservation" {
    const to: TrustObservation = .{
        .observer = [_]u8{0x06} ** 32,
        .about = [_]u8{0x07} ** 32,
    };
    try std.testing.expectEqual(@as(u32, 2), TrustObservation.format_version);
    try std.testing.expectEqualStrings("ball.trust-observation", TrustObservation.type_string);
    try std.testing.expectEqual(@as(usize, 0), to.axes.len);
    try std.testing.expectEqual(@as(usize, 0), to.signatures.len);
}

test "struct shape: Inscription" {
    const ins: Inscription = .{ .surface = "scroll" };
    try std.testing.expectEqual(@as(u32, 2), Inscription.format_version);
    try std.testing.expectEqualStrings("ball.inscription", Inscription.type_string);
    try std.testing.expectEqualStrings("scroll", ins.surface);
    try std.testing.expectEqualStrings("auto", ins.placement);
}

test "struct shape: Mythos" {
    const m: Mythos = .{ .is_genesis = true };
    try std.testing.expectEqual(@as(u32, 2), Mythos.format_version);
    try std.testing.expectEqualStrings("ball.mythos", Mythos.type_string);
    try std.testing.expect(m.is_genesis);
    try std.testing.expectEqual(@as(?[32]u8, null), m.predecessor);
    try std.testing.expectEqual(@as(?[32]u8, null), m.about);
}

test "struct shape: Archiform" {
    const ar: Archiform = .{ .form = "library" };
    try std.testing.expectEqual(@as(u32, 2), Archiform.format_version);
    try std.testing.expectEqualStrings("ball.archiform", Archiform.type_string);
    try std.testing.expectEqualStrings("library", ar.form);
    try std.testing.expectEqual(@as(?[]const u8, null), ar.parent_form);
}

// Dreamball-h7s.1 removed the "struct shape: Object3d", "AC2: field-kind
// palace and room preserved", "AC3: unknown field-kind preserved verbatim",
// and "AC4: palaceInvariants ..." tests along with the Object3d, FieldKind,
// and palaceInvariants/PalaceInvariantError types they exercised.

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
