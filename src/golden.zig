//! Golden-bytes lock — pins the canonical CBOR output of the DreamBall
//! encoder to a known Blake3 hash. Any future change that alters the
//! wire bytes must update these constants *and* be reviewed for
//! compatibility implications (version bump? breaking change?).

const std = @import("std");
const protocol = @import("protocol.zig");
const envelope = @import("envelope.zig");

/// Expected Blake3 hex hash for an all-zeros seed node:
///   stage = .seed
///   identity = [0] * 32
///   genesis_hash = [0] * 32
///   revision = 0
///   (no attributes — core only)
pub const GOLDEN_ZERO_SEED_BLAKE3: []const u8 = "df27762290f8b4dd2ac32fca17726483ecbe38b0a4ec954dd136de846f1c6998";

fn blake3Hex(bytes: []const u8) [64]u8 {
    var out: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(bytes);
    hasher.final(&out);
    var hex: [64]u8 = undefined;
    const charset = "0123456789abcdef";
    for (out, 0..) |b, i| {
        hex[i * 2] = charset[(b >> 4) & 0xF];
        hex[i * 2 + 1] = charset[b & 0xF];
    }
    return hex;
}

/// Pinned Blake3 for a canonical jelly.memory-connection envelope.
/// Core keys must emit in dCBOR order: to(2), from(4), kind(4), type(4), format-version(14).
/// If this fails, inspect writeMemoryConnection core-key ordering in envelope_v2.zig.
pub const GOLDEN_MEMORY_CONNECTION_BLAKE3: []const u8 = "d555eba7765504311b906ffdcf1c5df6bf8d3f3cb064fa205522d1c75f686255";

// ============================================================================
// §13.11 palace envelope golden-bytes fixtures
// ============================================================================
// AC4 reconciliation: PROTOCOL.md §13.11 says "thirteen new fixtures" but
// enumerates items 1–13 with sub-items 3a and 5a, yielding 15 distinct
// fixture shapes. This file locks all 15. The story AC1 constant list
// matches that count exactly. PROTOCOL.md §13.11 does not need editing —
// the numbered list simply uses sub-items (3a, 5a) as qualifying variants
// rather than top-level entries; the prose count of "thirteen" refers to the
// primary numbered items, not the variants. Resolution: lock all 15.

/// §13.11 fixture 1: jelly.dreamball.field with field-kind: "palace" attribute (minimal).
/// Minimal = all-zeros identity/genesis, stage=seed, revision=0, plus field-kind attr.
/// Core key ordering (len asc, lex): "type"(4), "stage"(5), "identity"(8),
/// "revision"(8) — "identity"<"revision" lex, "genesis-hash"(12), "format-version"(14).
pub const GOLDEN_PALACE_FIELD_BLAKE3: []const u8 = "928255750c7a9ddce8c3b8f9af5c48b82c4ba7ac73dffc60b5ee7c415946da9e";

/// §13.11 fixture 2: jelly.layout with two placements.
/// child_fp[0]=0x01*32 pos=[0,0,0] facing=[0,0,0,1]; child_fp[1]=0x02*32 pos=[1,0,0] facing=[0,0,0,1].
pub const GOLDEN_LAYOUT_BLAKE3: []const u8 = "b7c7e21febee5b6228ddc29c87cace8724e3d3b79eca3decb8c9d2c7b02678b7";

/// §13.11 fixture 3: jelly.timeline quiescent — 1-element head-hashes set (palace_fp=0*32, head=0xAA*32).
pub const GOLDEN_TIMELINE_QUIESCENT_BLAKE3: []const u8 = "c76ab80ad339385d74480814fc1fea95c1187e7c9366f4d886daaa546bc68896";

/// §13.11 fixture 3a: jelly.timeline concurrent — 2-element head-hashes (0xAA*32, 0xBB*32).
pub const GOLDEN_TIMELINE_CONCURRENT_BLAKE3: []const u8 = "ed39a504d213a59d7145da44bdb4050d65fc95496010a667e4e1b4db79875cce";

/// §13.11 fixture 4: jelly.action single-parent (palace_minted, actor=0x01*32, parent=0x10*32).
pub const GOLDEN_ACTION_SINGLE_PARENT_BLAKE3: []const u8 = "1616d260fdea9513b97f45f8775f1a08c85de7e4c36a8b71d09f297282318465";

/// §13.11 fixture 5: jelly.action multi-parent (move, actor=0x01*32, parents=[0x10*32, 0x11*32]).
pub const GOLDEN_ACTION_MULTI_PARENT_BLAKE3: []const u8 = "0054ef720f91382d44d880ae9dda4a530f292457fdb667a7ce726f607af05eff";

/// §13.11 fixture 5a: jelly.action with deps and nacks populated (inscription_updated, 1 dep, 1 nack).
pub const GOLDEN_ACTION_DEPS_NACKS_BLAKE3: []const u8 = "639a7e17a44e97917d487819cd588ac023c63ea77aa38a279d131c2f7d227d69";

/// §13.11 fixture 6: jelly.aqueduct with all numeric fields populated + conductance + phase=resonant.
pub const GOLDEN_AQUEDUCT_BLAKE3: []const u8 = "7a52f9a817e11d7000bb83c234bd768d353e3200ae1f66a3c02ba6edb83e057f";

/// §13.11 fixture 7: jelly.element-tag element="fire", phase="yang".
pub const GOLDEN_ELEMENT_TAG_BLAKE3: []const u8 = "1dd66944d26ec75735a1bf0f3b49d740ce3ddd2cdd35563db62ca8a32c9c7164";

/// §13.11 fixture 8: jelly.trust-observation two axes (reliability, alignment) + two ed25519 sigs.
pub const GOLDEN_TRUST_OBSERVATION_BLAKE3: []const u8 = "ef955f8d0bfccd8027936fafa2cef0c82b499891762f22e57d5049b6866db123";

/// §13.11 fixture 9: jelly.inscription surface="scroll", placement="curator", note=markdown text.
pub const GOLDEN_INSCRIPTION_BLAKE3: []const u8 = "b1348bf235bfccfdbc62f0312b5037e32c2c53e08210d2d1d79a0796b16d1001";

/// §13.11 fixture 10: jelly.mythos canonical genesis — is_genesis=true, no predecessor, no "about".
/// Has discovered_in ref + true_name + authored_at. CANONICAL mode per TC18.
pub const GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3: []const u8 = "dae4ef0ba2327fc72d0521db81316e5fee4e2a67a358876ec336339e91bbf300";

/// §13.11 fixture 11: jelly.mythos canonical successor — is_genesis=false, predecessor=0xCC*32,
/// synthesizes=[0xDD*32], discovered_in=0xEE*32. CANONICAL mode, no "about" attr.
pub const GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3: []const u8 = "e943d0eb62a6173cb991e752dc15843248e93c70dc8b16ec1d7fb220d1f46ba6";

/// §13.11 fixture 12: jelly.mythos poetic — is_genesis=true, about=0x05*32, form="invocation",
/// body text, author=0x01*32. POETIC mode per TC18 — "about" attr present.
pub const GOLDEN_MYTHOS_POETIC_BLAKE3: []const u8 = "5eddc62c7e7afe3c447b0e741a09b296fdf414f1bfa84426cc1cf581b5cea87a";

/// §13.11 fixture 13: jelly.archiform form="library", tradition="hermetic", parent_form="forge".
pub const GOLDEN_ARCHIFORM_BLAKE3: []const u8 = "641b289c1828980d77e3bd9aefedefcc87a7d7dd93b19a7841e450e4a79220fb";

// ============================================================================
// Pre-existing tests
// ============================================================================

test "golden bytes: all-zeros seed node (core only)" {
    const allocator = std.testing.allocator;
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{0} ** 32,
        .genesis_hash = [_]u8{0} ** 32,
        .revision = 0,
    };
    const bytes = try envelope.encodeDreamBall(allocator, db);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    // Print on mismatch so first-run generation is easy.
    std.testing.expectEqualSlices(u8, GOLDEN_ZERO_SEED_BLAKE3, &hex) catch |err| {
        std.debug.print("\n  GOLDEN MISMATCH\n  observed: {s}\n  expected: {s}\n  (update GOLDEN_ZERO_SEED_BLAKE3 in src/golden.zig if the change is intentional)\n", .{ hex, GOLDEN_ZERO_SEED_BLAKE3 });
        return err;
    };
}

test "golden bytes: jelly.memory-connection canonical ordering" {
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const m: v2.Memory = .{
        .nodes = &.{},
        .connections = &[_]v2.MemoryConnection{
            .{ .from = 1, .to = 2, .kind = .temporal, .strength = 0.5 },
        },
    };
    const bytes = try envelope_v2.encodeMemory(allocator, m);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    std.testing.expectEqualSlices(u8, GOLDEN_MEMORY_CONNECTION_BLAKE3, &hex) catch |err| {
        std.debug.print("\n  MEMORY-CONNECTION GOLDEN MISMATCH\n  observed: {s}\n  expected: {s}\n", .{ hex, GOLDEN_MEMORY_CONNECTION_BLAKE3 });
        return err;
    };
}

// ============================================================================
// §13.11 palace envelope golden tests
// ============================================================================

/// Shared drift-detection helper. On constant mismatch prints both hashes and
/// propagates the error ("GOLDEN MISMATCH" satisfies AC3). When constant equals
/// __RECOMPUTE_ON_FIRST_RUN__ the test prints observed hash and fails with
/// GoldenRecompute (satisfies AC2 bootstrap path).
fn goldenCheck(constant: []const u8, hex: [64]u8, name: []const u8) !void {
    if (std.mem.eql(u8, constant, "__RECOMPUTE_ON_FIRST_RUN__")) {
        std.debug.print("\n  {s} golden first run — commit this value:\n  {s}\n", .{ name, hex });
        return error.GoldenRecompute;
    }
    std.testing.expectEqualSlices(u8, constant, &hex) catch |err| {
        std.debug.print("\n  GOLDEN MISMATCH: {s}\n  observed: {s}\n  expected: {s}\n", .{ name, hex, constant });
        return err;
    };
}

test "golden bytes: jelly.dreamball.field with field-kind palace" {
    // §13.11 fixture 1 — jelly.dreamball.field minimal, field-kind: "palace".
    // Encoded directly with zbor/dcbor primitives because DreamBall does not
    // carry a field_kind slot (attribute-level addition per §13.1).
    const allocator = std.testing.allocator;
    const zbor = @import("zbor");
    const dcbor = @import("dcbor.zig");

    var ai = std.Io.Writer.Allocating.init(allocator);
    defer ai.deinit();
    const w = &ai.writer;

    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    try zbor.builder.writeArray(w, 2); // 1 core + 1 attribute
    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // Core keys sorted (len asc, lex): "type"(4), "stage"(5), "identity"(8),
    //   "revision"(8) — "identity" < "revision" lex, "genesis-hash"(12), "format-version"(14).
    try zbor.builder.writeMap(w, 6);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, "jelly.dreamball.field");
    try zbor.builder.writeTextString(w, "stage");
    try zbor.builder.writeTextString(w, "seed");
    try zbor.builder.writeTextString(w, "identity");
    try zbor.builder.writeByteString(w, &([_]u8{0} ** 32));
    try zbor.builder.writeTextString(w, "revision");
    try zbor.builder.writeInt(w, @as(u64, 0));
    try zbor.builder.writeTextString(w, "genesis-hash");
    try zbor.builder.writeByteString(w, &([_]u8{0} ** 32));
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @as(u64, 2));
    // attribute: ["field-kind", "palace"]
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "field-kind");
    try zbor.builder.writeTextString(w, "palace");

    const bytes = try ai.toOwnedSlice();
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_PALACE_FIELD_BLAKE3, hex, "GOLDEN_PALACE_FIELD_BLAKE3");
}

test "golden bytes: jelly.layout two placements" {
    // §13.11 fixture 2 — two placements with distinct child fingerprints.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const l = v2.Layout{
        .placements = &[_]v2.Placement{
            .{
                .child_fp = [_]u8{0x01} ** 32,
                .position = .{ 0.0, 0.0, 0.0 },
                .facing = .{ .qx = 0.0, .qy = 0.0, .qz = 0.0, .qw = 1.0 },
            },
            .{
                .child_fp = [_]u8{0x02} ** 32,
                .position = .{ 1.0, 0.0, 0.0 },
                .facing = .{ .qx = 0.0, .qy = 0.0, .qz = 0.0, .qw = 1.0 },
            },
        },
    };
    const bytes = try envelope_v2.encodeLayout(allocator, l);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_LAYOUT_BLAKE3, hex, "GOLDEN_LAYOUT_BLAKE3");
}

test "golden bytes: jelly.timeline quiescent (1 head-hash)" {
    // §13.11 fixture 3 — 1-element head-hashes set (quiescent — single writer).
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var heads = [_][32]u8{[_]u8{0xAA} ** 32};
    const t = v2.Timeline{
        .palace_fp = [_]u8{0} ** 32,
        .head_hashes = &heads,
    };
    const bytes = try envelope_v2.encodeTimeline(allocator, t);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_TIMELINE_QUIESCENT_BLAKE3, hex, "GOLDEN_TIMELINE_QUIESCENT_BLAKE3");
}

test "golden bytes: jelly.timeline concurrent (2 head-hashes)" {
    // §13.11 fixture 3a — 2-element head-hashes set (concurrent writers, unmerged).
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var heads = [_][32]u8{
        [_]u8{0xAA} ** 32,
        [_]u8{0xBB} ** 32,
    };
    const t = v2.Timeline{
        .palace_fp = [_]u8{0} ** 32,
        .head_hashes = &heads,
    };
    const bytes = try envelope_v2.encodeTimeline(allocator, t);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_TIMELINE_CONCURRENT_BLAKE3, hex, "GOLDEN_TIMELINE_CONCURRENT_BLAKE3");
}

test "golden bytes: jelly.action single-parent" {
    // §13.11 fixture 4 — single-parent palace-minted action.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    const a = v2.Action{
        .action_kind = .palace_minted,
        .actor = [_]u8{0x01} ** 32,
        .parent_hashes = &parents,
    };
    const bytes = try envelope_v2.encodeAction(allocator, a);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ACTION_SINGLE_PARENT_BLAKE3, hex, "GOLDEN_ACTION_SINGLE_PARENT_BLAKE3");
}

test "golden bytes: jelly.action multi-parent" {
    // §13.11 fixture 5 — multi-parent move action (2 parent hashes).
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var parents = [_][32]u8{
        [_]u8{0x10} ** 32,
        [_]u8{0x11} ** 32,
    };
    const a = v2.Action{
        .action_kind = .move,
        .actor = [_]u8{0x01} ** 32,
        .parent_hashes = &parents,
    };
    const bytes = try envelope_v2.encodeAction(allocator, a);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ACTION_MULTI_PARENT_BLAKE3, hex, "GOLDEN_ACTION_MULTI_PARENT_BLAKE3");
}

test "golden bytes: jelly.action deps and nacks" {
    // §13.11 fixture 5a — action with deps and nacks populated.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    var deps = [_]v2.ActionRef{[_]u8{0x20} ** 32};
    var nacks = [_]v2.ActionRef{[_]u8{0x30} ** 32};
    const a = v2.Action{
        .action_kind = .inscription_updated,
        .actor = [_]u8{0x01} ** 32,
        .parent_hashes = &parents,
        .deps = &deps,
        .nacks = &nacks,
    };
    const bytes = try envelope_v2.encodeAction(allocator, a);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ACTION_DEPS_NACKS_BLAKE3, hex, "GOLDEN_ACTION_DEPS_NACKS_BLAKE3");
}

test "golden bytes: jelly.aqueduct all numeric fields" {
    // §13.11 fixture 6 — aqueduct with all numeric fields populated.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const aq = v2.Aqueduct{
        .from = [_]u8{0x01} ** 32,
        .to = [_]u8{0x02} ** 32,
        .kind = "gaze",
        .capacity = 1.0,
        .strength = 0.5,
        .resistance = 0.3,
        .capacitance = 0.1,
        .conductance = 0.368,
        .phase = .resonant,
    };
    const bytes = try envelope_v2.encodeAqueduct(allocator, aq);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_AQUEDUCT_BLAKE3, hex, "GOLDEN_AQUEDUCT_BLAKE3");
}

test "golden bytes: jelly.element-tag with phase" {
    // §13.11 fixture 7 — element-tag with phase qualifier.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const et = v2.ElementTag{
        .element = "fire",
        .phase = "yang",
    };
    const bytes = try envelope_v2.encodeElementTag(allocator, et);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ELEMENT_TAG_BLAKE3, hex, "GOLDEN_ELEMENT_TAG_BLAKE3");
}

test "golden bytes: jelly.trust-observation two axes two signatures" {
    // §13.11 fixture 8 — two axes (reliability, alignment) + two ed25519 sigs.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const proto = @import("protocol.zig");
    const axes = [_]v2.TrustAxis{
        .{ .name = "reliability", .value = 0.8, .range = .{ 0.0, 1.0 } },
        .{ .name = "alignment", .value = 0.6, .range = .{ 0.0, 1.0 } },
    };
    const sig1_val = [_]u8{0xAA} ** 64;
    const sig2_val = [_]u8{0xBB} ** 64;
    const sigs = [_]proto.Signature{
        .{ .alg = "ed25519", .value = &sig1_val },
        .{ .alg = "ed25519", .value = &sig2_val },
    };
    const to = v2.TrustObservation{
        .observer = [_]u8{0x01} ** 32,
        .about = [_]u8{0x02} ** 32,
        .axes = &axes,
        .signatures = &sigs,
    };
    const bytes = try envelope_v2.encodeTrustObservation(allocator, to);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_TRUST_OBSERVATION_BLAKE3, hex, "GOLDEN_TRUST_OBSERVATION_BLAKE3");
}

test "golden bytes: jelly.inscription with markdown surface" {
    // §13.11 fixture 9 — inscription with markdown note as embedded content.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const ins = v2.Inscription{
        .surface = "scroll",
        .placement = "curator",
        .note = "# Hello\n\nA short markdown inscription.",
    };
    const bytes = try envelope_v2.encodeInscription(allocator, ins);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_INSCRIPTION_BLAKE3, hex, "GOLDEN_INSCRIPTION_BLAKE3");
}

test "golden bytes: jelly.mythos canonical genesis" {
    // §13.11 fixture 10 — canonical genesis: is_genesis=true, no predecessor,
    // no "about" (canonical mode per TC18). Has discovered_in + true_name + authored_at.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const m = v2.Mythos{
        .is_genesis = true,
        .discovered_in = [_]u8{0xCC} ** 32,
        .true_name = "The Palace of Remembered Light",
        .authored_at = 1_700_000_000,
    };
    const bytes = try envelope_v2.encodeMythos(allocator, m);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3, hex, "GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3");
}

test "golden bytes: jelly.mythos canonical successor" {
    // §13.11 fixture 11 — canonical successor: is_genesis=false, predecessor set,
    // synthesizes=[0xDD*32], discovered_in set. CANONICAL mode — no "about" attr.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var syn = [_][32]u8{[_]u8{0xDD} ** 32};
    const m = v2.Mythos{
        .is_genesis = false,
        .predecessor = [_]u8{0xCC} ** 32,
        .synthesizes = &syn,
        .discovered_in = [_]u8{0xEE} ** 32,
        .true_name = "The Forge of Quiet Thunder",
        .authored_at = 1_700_000_001,
    };
    const bytes = try envelope_v2.encodeMythos(allocator, m);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3, hex, "GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3");
}

test "golden bytes: jelly.mythos poetic" {
    // §13.11 fixture 12 — poetic mythos: is_genesis=true, "about" attr set (TC18 split).
    // POETIC mode — has "about"=0x05*32, form, body, author, authored_at.
    // Distinct from canonical fixtures per AC5.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const m = v2.Mythos{
        .is_genesis = true,
        .about = [_]u8{0x05} ** 32,
        .form = "invocation",
        .body = "In the palace of stars, the dreamer wakes.",
        .author = [_]u8{0x01} ** 32,
        .authored_at = 1_700_000_002,
    };
    const bytes = try envelope_v2.encodeMythos(allocator, m);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_MYTHOS_POETIC_BLAKE3, hex, "GOLDEN_MYTHOS_POETIC_BLAKE3");
}

test "golden bytes: jelly.archiform with parent-form" {
    // §13.11 fixture 13 — archiform with tradition + parent-form set.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    const ar = v2.Archiform{
        .form = "library",
        .tradition = "hermetic",
        .parent_form = "forge",
    };
    const bytes = try envelope_v2.encodeArchiform(allocator, ar);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ARCHIFORM_BLAKE3, hex, "GOLDEN_ARCHIFORM_BLAKE3");
}

test "AC5: mythos canonical-genesis, canonical-successor, poetic hashes are distinct" {
    // Verifies TC18 — canonical vs poetic mythos shapes produce different byte output.
    try std.testing.expect(!std.mem.eql(u8, GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3, GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3));
    try std.testing.expect(!std.mem.eql(u8, GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3, GOLDEN_MYTHOS_POETIC_BLAKE3));
    try std.testing.expect(!std.mem.eql(u8, GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3, GOLDEN_MYTHOS_POETIC_BLAKE3));
}
