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
pub const GOLDEN_ZERO_SEED_BLAKE3: []const u8 = "eba0571b4a39593d1c82007192af6675b9b33169c183c7bd0ef962344e8d45a3";

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

/// Pinned Blake3 for a canonical ball.memory-connection envelope.
/// Core keys must emit in dCBOR order: to(2), from(4), kind(4), type(4), format-version(14).
/// If this fails, inspect writeMemoryConnection core-key ordering in envelope_v2.zig.
pub const GOLDEN_MEMORY_CONNECTION_BLAKE3: []const u8 = "5822f18bf9ab2e35956fdeb8ee369bf6e8c6670d552a25963494745338e4e108";

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

/// §13.11 fixture 1: ball.dreamball.field with field-kind: "palace" attribute (minimal).
/// Minimal = all-zeros identity/genesis, stage=seed, revision=0, plus field-kind attr.
/// Core key ordering (len asc, lex): "type"(4), "stage"(5), "identity"(8),
/// "revision"(8) — "identity"<"revision" lex, "genesis-hash"(12), "format-version"(14).
pub const GOLDEN_PALACE_FIELD_BLAKE3: []const u8 = "c1fd9453cdb61a019cac89ddfad33c090553d39ed6cfe680436b4263f96e9ee7";

/// §13.11 fixture 2: ball.layout with two placements.
/// child_fp[0]=0x01*32 pos=[0,0,0] facing=[0,0,0,1]; child_fp[1]=0x02*32 pos=[1,0,0] facing=[0,0,0,1].
pub const GOLDEN_LAYOUT_BLAKE3: []const u8 = "00650c43112a278cefd356e1f442ad0a128b22dcbaf2dae67e00710a14aecde4";

/// §13.11 fixture 3: ball.timeline quiescent — 1-element head-hashes set (palace_fp=0*32, head=0xAA*32).
pub const GOLDEN_TIMELINE_QUIESCENT_BLAKE3: []const u8 = "6c094b282f8b695aac56a7c4e3c9010d4d664d96964da6536c4eb1f3fabd0639";

/// §13.11 fixture 3a: ball.timeline concurrent — 2-element head-hashes (0xAA*32, 0xBB*32).
pub const GOLDEN_TIMELINE_CONCURRENT_BLAKE3: []const u8 = "ff2ac3b68a9c203cd589b6ac73355239f87457a70fdcf102d6a92673ad8497eb";

/// §13.11 fixture 4: ball.action single-parent (palace_minted, actor=0x01*32, parent=0x10*32).
pub const GOLDEN_ACTION_SINGLE_PARENT_BLAKE3: []const u8 = "b28b972de27f857670b5bafc782c7a635fca34e5170026573b3ed4aa150ef26b";

/// §13.11 fixture 5: ball.action multi-parent (move, actor=0x01*32, parents=[0x10*32, 0x11*32]).
pub const GOLDEN_ACTION_MULTI_PARENT_BLAKE3: []const u8 = "a28288920342400cf68370092a913e0602ed3fb667c210be6e2549f76250d3c8";

/// §13.11 fixture 5a: ball.action with deps and nacks populated (inscription_updated, 1 dep, 1 nack).
pub const GOLDEN_ACTION_DEPS_NACKS_BLAKE3: []const u8 = "ea5fb1e975dcd9d3c229cfad27735bd3ab95751f29273284f4678098016bb619";

/// §13.11 fixture 6: ball.aqueduct with all numeric fields populated + conductance + phase=resonant.
pub const GOLDEN_AQUEDUCT_BLAKE3: []const u8 = "7990491e8fcf036abb7483bf1a799046d4913f8b212c1bde92c2d9c9700f9b82";

/// §13.11 fixture 7: ball.element-tag element="fire", phase="yang".
pub const GOLDEN_ELEMENT_TAG_BLAKE3: []const u8 = "78a9137a8bb1d9d95dcdf095750710cf19c4789a1b6ea9ea128221e6ddb0a525";

/// §13.11 fixture 8: ball.trust-observation two axes (reliability, alignment) + two ed25519 sigs.
pub const GOLDEN_TRUST_OBSERVATION_BLAKE3: []const u8 = "b1b3418348b9aaf53023ccdee6b5789a26ef949d138d47bbcc6cf0835804bf9e";

/// §13.11 fixture 9: ball.inscription surface="scroll", placement="curator", note=markdown text.
pub const GOLDEN_INSCRIPTION_BLAKE3: []const u8 = "b964f3ea4abec72e0accde1f724babfa83969957d6cb70fc4f2137561c809630";

/// §13.11 fixture 10: ball.mythos canonical genesis — is_genesis=true, no predecessor, no "about".
/// Has discovered_in ref + true_name + authored_at. CANONICAL mode per TC18.
pub const GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3: []const u8 = "fe8c50a4ddd1b523f871402463a8223f96e88b0e6cabfc0b1b60c506dcc36f1f";

/// §13.11 fixture 11: ball.mythos canonical successor — is_genesis=false, predecessor=0xCC*32,
/// synthesizes=[0xDD*32], discovered_in=0xEE*32. CANONICAL mode, no "about" attr.
pub const GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3: []const u8 = "3b95274941bdcc60d02c2fc03ea03293817d17607f3f588365eea3cdb3bf47fb";

/// §13.11 fixture 12: ball.mythos poetic — is_genesis=true, about=0x05*32, form="invocation",
/// body text, author=0x01*32. POETIC mode per TC18 — "about" attr present.
pub const GOLDEN_MYTHOS_POETIC_BLAKE3: []const u8 = "dc25f30643c7ff9b048c1669f7faf1eeec03fc9a1db54b28add140d88ddcc254";

/// §13.11 fixture 13: ball.archiform form="library", tradition="hermetic", parent_form="forge".
pub const GOLDEN_ARCHIFORM_BLAKE3: []const u8 = "bae68c293a382bd085378bcc2f3f3e3c33e215c703ccaf3131d7389ad590465d";

// ============================================================================
// D1 — `ball.object3d` golden (sprint-003 stretch)
// ============================================================================
// Second maintainer-authored type proving the Zig-canonical pipeline
// generalizes. Fixed fixture: mesh "glb:tree-01", position [1,2,3], identity
// rotation [0,0,0,1], unit scale [1,1,1]. The TS-side mirror of these bytes
// lives in `src/lib/__fixtures__/object3d.golden.json`; the cross-runtime
// Vitest (`src/lib/object3d-codegen.test.ts`) decodes them via the generated
// `decodeObject3d` and validates via the generated `Object3dSchema`, forcing
// the Zig and TS golden copies to agree.

/// Canonical dCBOR `ball.object3d` envelope bytes for the fixed fixture.
pub const GOLDEN_OBJECT3D_BYTES_HEX: []const u8 = "d8c881d8c9a6646d6573686b676c623a747265652d303164747970656d62616c6c2e6f626a6563743364657363616c6583f93c00f93c00f93c0068706f736974696f6e83f93c00f94000f9420068726f746174696f6e84f90000f90000f90000f93c006e666f726d61742d76657273696f6e02";

/// blake3 of GOLDEN_OBJECT3D_BYTES_HEX bytes.
pub const GOLDEN_OBJECT3D_BLAKE3: []const u8 = "eec27f4c4e8cb4306e7ab74290fe37b8ad891bb2716f1e02d3bb703a9039feba";

// ============================================================================
// C1 — v4 `ball.action` content_hash cross-runtime golden (sprint-003)
// ============================================================================
// The op log's whole point is portable op identity: the SAME logical v4 action
// must hash identically across the Zig CLI, browser WASM, and Bun WASM (NFR1).
//
// **Which bytes are hashed (the content_hash domain).** `content_hash =
// Blake3-256(canonical UNSIGNED v4 envelope bytes)`, with NO domain-separation
// prefix (D-043, PROTOCOL.md §16.7/§17.4). The UNSIGNED bytes are exactly what
// `encodeActionV4` emits — `encodeActionV4Signed(a, &.{})`. Signatures are NOT
// covered: a verifier strips the `signed` attributes and recomputes over these
// same unsigned bytes, exactly as for DreamBall envelopes (PROTOCOL.md §2.3).
//
// **Why three constants.** The WASM `authorAction` export emits a SIGNED
// envelope (Ed25519 is deterministic for a fixed seed), so the cross-runtime
// gate compares like-for-like at two levels: (1) the SIGNED bytes that
// `authorAction` returns must be byte-identical CLI≡WASM, and (2) the UNSIGNED
// bytes — the content_hash domain — and their digest must agree. The signed and
// unsigned encodings share an identical leaf+core block (they differ only in the
// outer array length header and the trailing `signed` attribute), so locking
// both pins the canonical encoder end to end.
//
// Fixture (the B1 reference KAT, reused for consistency): kind
// "worldtree.kanban-card.move", body = canonical CBOR `[1, 2]` (0x82 0x01 0x02),
// one parent 0x10*32, hlc `[1700000000000, 7]`, actor = Ed25519 public key of
// the all-zeros 32-byte seed. The TS-side mirror of these constants lives in
// `src/lib/wasm/__fixtures__/action-v4.golden.json`; the cross-runtime tests
// force the two copies to agree (any drift fails a gate on one side or the other).

/// Ed25519 public key of the all-zeros 32-byte seed = the fixture's `actor`.
pub const GOLDEN_ACTION_V4_ACTOR_HEX: []const u8 = "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29";

/// Canonical UNSIGNED v4 `ball.action` envelope bytes — the content_hash domain.
pub const GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX: []const u8 = "d8c881d8c9a763686c63821b0000018bcfe568000764626f647943820102646b696e64781a776f726c64747265652e6b616e62616e2d636172642e6d6f766564747970656b62616c6c2e616374696f6e656163746f7258203b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da296d706172656e742d68617368657381582010101010101010101010101010101010101010101010101010101010101010106e666f726d61742d76657273696f6e04";

/// content_hash = Blake3-256(GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX), no domain prefix.
pub const GOLDEN_ACTION_V4_CONTENT_HASH: []const u8 = "5b97ee37cd5fc24ee7e88c96d6613dadf9fafe4ebea5429ac328af133e2fd27b";

/// Canonical SIGNED v4 envelope bytes — exactly what WASM `authorAction` returns
/// for the all-zeros seed (deterministic Ed25519 signature over the unsigned bytes).
pub const GOLDEN_ACTION_V4_SIGNED_BYTES_HEX: []const u8 = "d8c882d8c9a763686c63821b0000018bcfe568000764626f647943820102646b696e64781a776f726c64747265652e6b616e62616e2d636172642e6d6f766564747970656b62616c6c2e616374696f6e656163746f7258203b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da296d706172656e742d68617368657381582010101010101010101010101010101010101010101010101010101010101010106e666f726d61742d76657273696f6e0482667369676e656482676564323535313958409c6046ab78bebcb744ed214fa0e44f362e0853a15360c8c781458230058f1aaa771da72aaeb20e95a35cf42c0a0188e7bcc257710220306d30b9202d72bbde03";

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

test "golden bytes: ball.memory-connection canonical ordering" {
    const allocator = std.testing.allocator;
    const m: protocol.Memory = .{
        .nodes = &.{},
        .connections = &[_]protocol.MemoryConnection{
            .{ .from = 1, .to = 2, .kind = .temporal, .strength = 0.5 },
        },
    };
    const bytes = try envelope.encodeMemory(allocator, m);
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

test "golden bytes: ball.dreamball.field with field-kind palace" {
    // §13.11 fixture 1 — ball.dreamball.field minimal, field-kind: "palace".
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
    try zbor.builder.writeTextString(w, "ball.dreamball.field");
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

test "golden bytes: ball.layout two placements" {
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

test "golden bytes: ball.timeline quiescent (1 head-hash)" {
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

test "golden bytes: ball.timeline concurrent (2 head-hashes)" {
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

test "golden bytes: ball.action single-parent" {
    // §13.11 fixture 4 — single-parent palace-minted action.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    const a = v2.Action{
        .kind = v2.ActionKind.palace_minted.toWireString(),
        .actor = [_]u8{0x01} ** 32,
        .parent_hashes = &parents,
        .hlc = .{ 0, 0 },
    };
    const bytes = try envelope_v2.encodeAction(allocator, a);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ACTION_SINGLE_PARENT_BLAKE3, hex, "GOLDEN_ACTION_SINGLE_PARENT_BLAKE3");
}

test "golden bytes: ball.action multi-parent" {
    // §13.11 fixture 5 — multi-parent move action (2 parent hashes).
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var parents = [_][32]u8{
        [_]u8{0x10} ** 32,
        [_]u8{0x11} ** 32,
    };
    const a = v2.Action{
        .kind = v2.ActionKind.move.toWireString(),
        .actor = [_]u8{0x01} ** 32,
        .parent_hashes = &parents,
        .hlc = .{ 0, 0 },
    };
    const bytes = try envelope_v2.encodeAction(allocator, a);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ACTION_MULTI_PARENT_BLAKE3, hex, "GOLDEN_ACTION_MULTI_PARENT_BLAKE3");
}

test "golden bytes: ball.action deps and nacks" {
    // §13.11 fixture 5a — action with deps and nacks populated.
    const allocator = std.testing.allocator;
    const v2 = @import("protocol_v2.zig");
    const envelope_v2 = @import("envelope_v2.zig");
    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    var deps = [_]v2.ActionRef{[_]u8{0x20} ** 32};
    var nacks = [_]v2.ActionRef{[_]u8{0x30} ** 32};
    const a = v2.Action{
        .kind = v2.ActionKind.inscription_updated.toWireString(),
        .actor = [_]u8{0x01} ** 32,
        .parent_hashes = &parents,
        .hlc = .{ 0, 0 },
        .deps = &deps,
        .nacks = &nacks,
    };
    const bytes = try envelope_v2.encodeAction(allocator, a);
    defer allocator.free(bytes);
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_ACTION_DEPS_NACKS_BLAKE3, hex, "GOLDEN_ACTION_DEPS_NACKS_BLAKE3");
}

test "golden bytes: ball.aqueduct all numeric fields" {
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

test "golden bytes: ball.element-tag with phase" {
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

test "golden bytes: ball.trust-observation two axes two signatures" {
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

test "golden bytes: ball.inscription with markdown surface" {
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

test "golden bytes: ball.mythos canonical genesis" {
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

test "golden bytes: ball.mythos canonical successor" {
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

test "golden bytes: ball.mythos poetic" {
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

test "golden bytes: ball.archiform with parent-form" {
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

/// Format `bytes` as lowercase hex into a caller-freed buffer.
fn hexAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, bytes.len * 2);
    const charset = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        buf[i * 2] = charset[(b >> 4) & 0xF];
        buf[i * 2 + 1] = charset[b & 0xF];
    }
    return buf;
}

/// Assert `bytes` hex-encodes to `expected_hex`; prints both on mismatch.
fn expectHexEql(expected_hex: []const u8, bytes: []const u8, name: []const u8) !void {
    const allocator = std.testing.allocator;
    const got = try hexAlloc(allocator, bytes);
    defer allocator.free(got);
    std.testing.expectEqualSlices(u8, expected_hex, got) catch |err| {
        std.debug.print("\n  C1 GOLDEN MISMATCH: {s}\n  observed: {s}\n  expected: {s}\n", .{ name, got, expected_hex });
        return err;
    };
}

/// Build the C1 fixture Action with the all-zeros-seed keypair. Returns the
/// keypair alongside so the caller can sign. `parents` and `body` are borrowed
/// from caller-owned storage (the slices below are pointers into the args).
fn c1FixtureAction(
    parents: *[1][32]u8,
    body: []const u8,
    kp: std.crypto.sign.Ed25519.KeyPair,
) @import("protocol_v2.zig").Action {
    const v2 = @import("protocol_v2.zig");
    return v2.Action{
        .kind = "worldtree.kanban-card.move",
        .parent_hashes = parents,
        .actor = kp.public_key.toBytes(),
        .body = body,
        .hlc = .{ 1_700_000_000_000, 7 },
    };
}

test "C1 golden: v4 ball.action content_hash + signed bytes (CLI ≡ Zig side)" {
    // AC2/AC3: the Zig CLI encoder produces the exact pinned canonical bytes and
    // content_hash. content_hash is Blake3 over the UNSIGNED envelope (D-043) —
    // see the C1 header comment for why the unsigned bytes are the domain.
    const allocator = std.testing.allocator;
    const envelope_v2 = @import("envelope_v2.zig");
    const proto = @import("protocol.zig");
    const Ed25519 = std.crypto.sign.Ed25519;

    const seed: [Ed25519.KeyPair.seed_length]u8 = .{0} ** Ed25519.KeyPair.seed_length;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);
    const actor = kp.public_key.toBytes();
    // The actor is the all-zeros-seed public key — pin it so the TS fixture's
    // `actorHex` (which it must reuse to build the same secret) is anchored here.
    try expectHexEql(GOLDEN_ACTION_V4_ACTOR_HEX, &actor, "actor");

    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    const body = [_]u8{ 0x82, 0x01, 0x02 }; // canonical CBOR array [1, 2]
    const a = c1FixtureAction(&parents, &body, kp);

    // (1) Canonical UNSIGNED bytes — the content_hash domain.
    const unsigned = try envelope_v2.encodeActionV4(allocator, a);
    defer allocator.free(unsigned);
    try expectHexEql(GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX, unsigned, "unsigned bytes");

    // (2) content_hash = Blake3(unsigned), no domain prefix.
    const ch = blake3Hex(unsigned);
    try std.testing.expectEqualSlices(u8, GOLDEN_ACTION_V4_CONTENT_HASH, &ch);
    // …and via the named helper, which is what consumers call (AC1).
    const ch2 = try envelope_v2.contentHash(allocator, a);
    try expectHexEql(GOLDEN_ACTION_V4_CONTENT_HASH, &ch2, "contentHash() helper");

    // (3) SIGNED bytes — what WASM authorAction returns (deterministic Ed25519).
    const sig = (try kp.sign(unsigned, null)).toBytes();
    const sigs = [_]proto.Signature{.{ .alg = "ed25519", .value = &sig }};
    const signed = try envelope_v2.encodeActionV4Signed(allocator, a, &sigs);
    defer allocator.free(signed);
    try expectHexEql(GOLDEN_ACTION_V4_SIGNED_BYTES_HEX, signed, "signed bytes");

    // The signed and unsigned encodings share an identical leaf+core block
    // (offset 3 = 2-byte envelope tag + 1-byte outer-array header). This is the
    // invariant the WASM cross-runtime test relies on to recover the content_hash
    // domain from authorAction's signed output without a second encode path.
    try std.testing.expectEqualSlices(u8, unsigned[3..], signed[3 .. unsigned.len]);
}

test "C1 negative: a one-byte body perturbation flips content_hash" {
    // AC (test plan): an intentional one-byte change must change the digest.
    const allocator = std.testing.allocator;
    const envelope_v2 = @import("envelope_v2.zig");
    const Ed25519 = std.crypto.sign.Ed25519;

    const seed: [Ed25519.KeyPair.seed_length]u8 = .{0} ** Ed25519.KeyPair.seed_length;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);

    var parents = [_][32]u8{[_]u8{0x10} ** 32};
    const body = [_]u8{ 0x82, 0x01, 0x03 }; // [1, 3] — one byte differs from the fixture's [1, 2]
    const a = c1FixtureAction(&parents, &body, kp);
    const ch = try envelope_v2.contentHash(allocator, a);
    const got = try hexAlloc(allocator, &ch);
    defer allocator.free(got);
    try std.testing.expect(!std.mem.eql(u8, GOLDEN_ACTION_V4_CONTENT_HASH, got));
}

test "D1 golden: ball.object3d canonical bytes + blake3" {
    // Fixed fixture (mirrored in src/lib/__fixtures__/object3d.golden.json).
    const allocator = std.testing.allocator;
    const envelope_v2 = @import("envelope_v2.zig");
    const v2 = @import("protocol_v2.zig");

    const o = v2.Object3d{
        .mesh = "glb:tree-01",
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ .qx = 0, .qy = 0, .qz = 0, .qw = 1 },
        .scale = .{ 1.0, 1.0, 1.0 },
    };
    const bytes = try envelope_v2.encodeObject3d(allocator, o);
    defer allocator.free(bytes);
    try expectHexEql(GOLDEN_OBJECT3D_BYTES_HEX, bytes, "object3d bytes");
    const hex = blake3Hex(bytes);
    try goldenCheck(GOLDEN_OBJECT3D_BLAKE3, hex, "GOLDEN_OBJECT3D_BLAKE3");
}

test "AC5: mythos canonical-genesis, canonical-successor, poetic hashes are distinct" {
    // Verifies TC18 — canonical vs poetic mythos shapes produce different byte output.
    try std.testing.expect(!std.mem.eql(u8, GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3, GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3));
    try std.testing.expect(!std.mem.eql(u8, GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3, GOLDEN_MYTHOS_POETIC_BLAKE3));
    try std.testing.expect(!std.mem.eql(u8, GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3, GOLDEN_MYTHOS_POETIC_BLAKE3));
}
