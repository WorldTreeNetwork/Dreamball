//! Core DreamBall domain types.
//! Wire format: see docs/PROTOCOL.md.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Fingerprint = @import("fingerprint.zig").Fingerprint;

pub const FORMAT_VERSION: u32 = 1;
/// Format version bumped when a node opts into the post-quantum
/// `identity-pq` core field. Semantically additive — v2 parsers reject with
/// `UnsupportedVersion`, which is what we want rather than silently dropping
/// the PQ pubkey.
pub const FORMAT_VERSION_V3: u32 = 3;

/// Protocol v2 — typed DreamBalls and new auxiliary envelopes. See
/// docs/PROTOCOL.md §12. Every v2 envelope type uses this version number.
pub const FORMAT_VERSION_V2: u32 = 2;

/// The six DreamBall categories. Each changes which attributes the consumer
/// expects and which renderer lens it maps to. See docs/VISION.md §10.
pub const DreamBallType = enum {
    avatar,
    agent,
    tool,
    relic,
    field,
    guild,

    pub fn toWireString(self: DreamBallType) []const u8 {
        return switch (self) {
            .avatar => "jelly.dreamball.avatar",
            .agent => "jelly.dreamball.agent",
            .tool => "jelly.dreamball.tool",
            .relic => "jelly.dreamball.relic",
            .field => "jelly.dreamball.field",
            .guild => "jelly.dreamball.guild",
        };
    }

    pub fn fromWireString(s: []const u8) ?DreamBallType {
        if (std.mem.eql(u8, s, "jelly.dreamball.avatar")) return .avatar;
        if (std.mem.eql(u8, s, "jelly.dreamball.agent")) return .agent;
        if (std.mem.eql(u8, s, "jelly.dreamball.tool")) return .tool;
        if (std.mem.eql(u8, s, "jelly.dreamball.relic")) return .relic;
        if (std.mem.eql(u8, s, "jelly.dreamball.field")) return .field;
        if (std.mem.eql(u8, s, "jelly.dreamball.guild")) return .guild;
        return null;
    }

    /// Short human-readable tag used in CLI output.
    pub fn tag(self: DreamBallType) []const u8 {
        return switch (self) {
            .avatar => "avatar",
            .agent => "agent",
            .tool => "tool",
            .relic => "relic",
            .field => "field",
            .guild => "guild",
        };
    }

    pub fn fromTag(s: []const u8) ?DreamBallType {
        if (std.mem.eql(u8, s, "avatar")) return .avatar;
        if (std.mem.eql(u8, s, "agent")) return .agent;
        if (std.mem.eql(u8, s, "tool")) return .tool;
        if (std.mem.eql(u8, s, "relic")) return .relic;
        if (std.mem.eql(u8, s, "field")) return .field;
        if (std.mem.eql(u8, s, "guild")) return .guild;
        return null;
    }
};

/// Ed25519 signature length (bytes).
pub const ED25519_SIGNATURE_LEN: usize = 64;
/// ML-DSA-87 signature length (bytes), per NIST FIPS 204 level-5.
pub const ML_DSA_87_SIGNATURE_LEN: usize = 4627;
/// ML-DSA-87 public key length (bytes).
pub const ML_DSA_87_PUBLIC_KEY_LEN: usize = 2592;
/// ML-DSA-87 secret key length (bytes).
pub const ML_DSA_87_SECRET_KEY_LEN: usize = 4896;

pub const Stage = enum {
    seed,
    dreamball,
    dragonball,

    pub fn toString(self: Stage) []const u8 {
        return switch (self) {
            .seed => "seed",
            .dreamball => "dreamball",
            .dragonball => "dragonball",
        };
    }

    pub fn fromString(s: []const u8) ?Stage {
        if (std.mem.eql(u8, s, "seed")) return .seed;
        if (std.mem.eql(u8, s, "dreamball")) return .dreamball;
        if (std.mem.eql(u8, s, "dragonball")) return .dragonball;
        return null;
    }
};

pub const Asset = struct {
    media_type: []const u8,
    hash: [32]u8,
    urls: []const []const u8 = &.{},
    embedded: ?[]const u8 = null,
    size: ?u64 = null,
    note: ?[]const u8 = null,

    pub fn deinit(self: *Asset, allocator: Allocator) void {
        allocator.free(self.media_type);
        for (self.urls) |u| allocator.free(u);
        allocator.free(self.urls);
        if (self.embedded) |e| allocator.free(e);
        if (self.note) |n| allocator.free(n);
        self.* = undefined;
    }
};

pub const Look = struct {
    assets: []const Asset = &.{},
    preview: ?Asset = null,
    background: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

pub const Feel = struct {
    personality: ?[]const u8 = null,
    voice: ?[]const u8 = null,
    values: []const []const u8 = &.{},
    tempo: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

pub const Skill = struct {
    name: []const u8,
    trigger: ?[]const u8 = null,
    body: ?[]const u8 = null,
    asset: ?Asset = null,
    requires: []const []const u8 = &.{},
    note: ?[]const u8 = null,
};

pub const Act = struct {
    model: ?[]const u8 = null,
    system_prompt: ?[]const u8 = null,
    skills: []const Skill = &.{},
    scripts: []const Asset = &.{},
    tools: []const []const u8 = &.{},
    note: ?[]const u8 = null,
};

pub const Signature = struct {
    /// "ed25519" or "ml-dsa-87"
    alg: []const u8,
    value: []const u8,
};

/// In-memory DreamBall. Pure data, no I/O.
pub const DreamBall = struct {
    stage: Stage,
    /// Ed25519 public key — the container's identity.
    identity: [32]u8,
    /// Post-quantum identity — the ML-DSA-87 public key (2592 bytes).
    /// Optional; present only on nodes that opted into PQ signing. The
    /// ML-DSA `'signed'` attribute verifies against this pubkey. Forcing
    /// format-version=3 (see `FORMAT_VERSION_V3`) guarantees old parsers
    /// reject the node rather than silently ignore the PQ pubkey.
    identity_pq: ?[ML_DSA_87_PUBLIC_KEY_LEN]u8 = null,
    /// Blake3 of the canonical seed payload. Immutable across the lifetime.
    genesis_hash: [32]u8,
    /// Monotonic, bumped on every signed update.
    revision: u32 = 0,
    /// v2 — the DreamBall's category. Null means untyped (v1 legacy shape;
    /// consumers treat null as `.avatar`).
    dreamball_type: ?DreamBallType = null,
    name: ?[]const u8 = null,
    created: ?i64 = null,
    updated: ?i64 = null,
    note: ?[]const u8 = null,
    look: ?Look = null,
    feel: ?Feel = null,
    act: ?Act = null,
    /// Fingerprints of Guilds claiming this DreamBall (per-slot policy
    /// resolution walks through these — see docs/PROTOCOL.md §12.7).
    guilds: []const Fingerprint = &.{},
    /// Fingerprints of DreamBalls this one contains (graph edges).
    contains: []const Fingerprint = &.{},
    /// Fingerprints of DreamBalls this one is derived from.
    derived_from: []const Fingerprint = &.{},
    signatures: []const Signature = &.{},

    pub fn fingerprint(self: DreamBall) Fingerprint {
        return Fingerprint.fromEd25519(self.identity);
    }

    pub const SignedPolicy = enum {
        /// Require real Ed25519 **and** real ML-DSA-87. The production default.
        strict,
        /// Accept a zero-filled ML-DSA-87 placeholder alongside a real Ed25519.
        /// Used in tests and dev tooling until the liboqs binding lands.
        allow_mldsa_placeholder,
    };

    /// A DreamBall is "signed" iff it has one real Ed25519 + one real ML-DSA-87
    /// signature attached. Both-required is recrypt's rule, inherited.
    ///
    /// The ML-DSA-87 slot may be a zero-filled placeholder while the liboqs
    /// binding is pending — pass `.allow_mldsa_placeholder` to accept it.
    pub fn isFullySigned(self: DreamBall, policy: SignedPolicy) bool {
        var have_real_ed = false;
        var have_real_mldsa = false;
        var have_placeholder_mldsa = false;
        for (self.signatures) |s| {
            if (std.mem.eql(u8, s.alg, "ed25519")) {
                if (s.value.len == ED25519_SIGNATURE_LEN) have_real_ed = true;
            } else if (std.mem.eql(u8, s.alg, "ml-dsa-87")) {
                if (s.value.len == ML_DSA_87_SIGNATURE_LEN) {
                    if (isZeroBytes(s.value)) have_placeholder_mldsa = true else have_real_mldsa = true;
                }
            }
        }
        if (have_real_ed and have_real_mldsa) return true;
        if (have_real_ed and have_placeholder_mldsa and policy == .allow_mldsa_placeholder) return true;
        return false;
    }
};

fn isZeroBytes(bytes: []const u8) bool {
    for (bytes) |b| if (b != 0) return false;
    return true;
}

test "stage round-trip" {
    try std.testing.expectEqualStrings("seed", Stage.seed.toString());
    try std.testing.expectEqual(Stage.dreamball, Stage.fromString("dreamball").?);
    try std.testing.expect(Stage.fromString("nonsense") == null);
}

test "dreamball fingerprint matches identity" {
    const pk: [32]u8 = [_]u8{7} ** 32;
    const db = DreamBall{
        .stage = .seed,
        .identity = pk,
        .genesis_hash = [_]u8{0} ** 32,
    };
    const fp = db.fingerprint();
    const expected = Fingerprint.fromEd25519(pk);
    try std.testing.expect(fp.eql(expected));
}

test "isFullySigned rejects empty/wrong-length signatures" {
    const sigs_one = [_]Signature{.{ .alg = "ed25519", .value = "" }};
    const db_one = DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
        .signatures = &sigs_one,
    };
    try std.testing.expect(!db_one.isFullySigned(.strict));

    const sigs_both_empty = [_]Signature{
        .{ .alg = "ed25519", .value = "" },
        .{ .alg = "ml-dsa-87", .value = "" },
    };
    const db_both_empty = DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
        .signatures = &sigs_both_empty,
    };
    try std.testing.expect(!db_both_empty.isFullySigned(.strict));
}

test "isFullySigned accepts real Ed25519 + real ML-DSA-87" {
    const ed_sig: [ED25519_SIGNATURE_LEN]u8 = [_]u8{0x11} ** ED25519_SIGNATURE_LEN;
    const mldsa_sig: [ML_DSA_87_SIGNATURE_LEN]u8 = [_]u8{0x22} ** ML_DSA_87_SIGNATURE_LEN;
    const sigs = [_]Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = &mldsa_sig },
    };
    const db = DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
        .signatures = &sigs,
    };
    try std.testing.expect(db.isFullySigned(.strict));
}

test "isFullySigned: placeholder accepted only under allow_mldsa_placeholder" {
    const ed_sig: [ED25519_SIGNATURE_LEN]u8 = [_]u8{0x33} ** ED25519_SIGNATURE_LEN;
    const mldsa_placeholder: [ML_DSA_87_SIGNATURE_LEN]u8 = [_]u8{0} ** ML_DSA_87_SIGNATURE_LEN;
    const sigs = [_]Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = &mldsa_placeholder },
    };
    const db = DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
        .signatures = &sigs,
    };
    try std.testing.expect(!db.isFullySigned(.strict));
    try std.testing.expect(db.isFullySigned(.allow_mldsa_placeholder));
}
