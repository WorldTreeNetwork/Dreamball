//! export-golden-fixtures — writes fixtures/goldens/manifest.json
//!
//! Extracts the 20 named golden vectors currently pinned as ZIG TEST CODE in
//! `src/golden.zig` into a toolchain-neutral, on-disk manifest so a future
//! Rust implementation (bc-envelope / dcbor) can construct the same logical
//! values and compare bytes WITHOUT running Zig at all (Dreamball-y4t.8).
//!
//! Each manifest entry carries:
//!   - `name`           — a short identifier matching the golden.zig constant
//!                        (minus the `GOLDEN_`/`_BLAKE3` decoration).
//!   - `type`           — the `ball.*` wire type string.
//!   - `format_version` — the `format-version` core-map value the encoder emits.
//!   - `value`          — THE LOGICAL VALUE AS JSON. This is the important
//!                        part: it is what lets a from-scratch implementation
//!                        (e.g. a Rust one) construct the same input without
//!                        reading any Zig source. Byte strings are hex; there
//!                        is no base58/CBOR-specific encoding here.
//!   - `bytes_hex`      — the FULL canonical encoded bytes (not just a hash),
//!                        produced by the same Zig encoder `src/golden.zig`
//!                        pins.
//!   - `blake3`         — Blake3-256 of `bytes_hex`, hex-encoded.
//!   - `note`           — present only on entries needing a caveat (e.g. the
//!                        C1 action-v4 fixtures, whose actor/signature is
//!                        derived from a PUBLIC, deterministic Ed25519 test
//!                        seed — reproducible in any RFC 8032 implementation,
//!                        not a secret and not a reason to skip the fixture).
//!
//! IMPORTANT — re-baselining posture (see fixtures/goldens/README.md):
//! this manifest's `bytes_hex`/`blake3` are NOT an authoritative "Zig is
//! right" ratchet. There are no consumers of this application yet, so a
//! future Zig-vs-Rust divergence is far more likely to mean the Zig encoder
//! was wrong than that bc-envelope is wrong. When the Rust comparison run
//! finds a diff: investigate, and unless it is a genuine semantic
//! regression, RE-BASELINE this file against the Rust output and record why
//! in the `note` field / README, not the other way around.
//!
//! Run via:
//!   zig build export-golden-fixtures
//!
//! Output: fixtures/goldens/manifest.json (deterministic — no timestamps, no
//! map-ordering nondeterminism; every field is written in a fixed order so
//! two consecutive runs produce byte-identical output).

const std = @import("std");
const dreamball = @import("dreamball");
const zbor = @import("zbor");

const protocol = dreamball.protocol;
const v2 = dreamball.protocol_v2;
const ev2 = dreamball.envelope_v2;
const dcbor = dreamball.dcbor;
const golden = dreamball.golden;

const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;

/// Small string-builder wrapping the 0.16 unmanaged `std.ArrayList(u8)` API
/// (same shape as `src/json.zig`'s `Buf` — kept local since this tool has no
/// other JSON-writing callers).
const Buf = struct {
    allocator: Allocator,
    inner: std.ArrayList(u8),

    fn init(allocator: Allocator) Buf {
        return .{ .allocator = allocator, .inner = .empty };
    }

    fn deinit(self: *Buf) void {
        self.inner.deinit(self.allocator);
    }

    fn toOwned(self: *Buf) ![]u8 {
        return self.inner.toOwnedSlice(self.allocator);
    }

    fn writeByte(self: *Buf, b: u8) !void {
        try self.inner.append(self.allocator, b);
    }

    fn writeAll(self: *Buf, s: []const u8) !void {
        try self.inner.appendSlice(self.allocator, s);
    }

    fn print(self: *Buf, comptime fmt: []const u8, args: anytype) !void {
        const written = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(written);
        try self.inner.appendSlice(self.allocator, written);
    }
};

fn writeEscapedString(buf: *Buf, s: []const u8) !void {
    try buf.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.writeAll("\\\""),
            '\\' => try buf.writeAll("\\\\"),
            '\n' => try buf.writeAll("\\n"),
            '\r' => try buf.writeAll("\\r"),
            '\t' => try buf.writeAll("\\t"),
            0...0x08, 0x0B, 0x0C, 0x0E...0x1F => try buf.print("\\u{x:0>4}", .{c}),
            else => try buf.writeByte(c),
        }
    }
    try buf.writeByte('"');
}

fn hexAlloc(allocator: Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    const charset = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = charset[(b >> 4) & 0xF];
        out[i * 2 + 1] = charset[b & 0xF];
    }
    return out;
}

fn blake3HexAlloc(allocator: Allocator, bytes: []const u8) ![]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &out, .{});
    return hexAlloc(allocator, &out);
}

fn writeHexField(buf: *Buf, indent: []const u8, key: []const u8, bytes: []const u8, comma: bool) !void {
    const hex = try hexAlloc(buf.allocator, bytes);
    defer buf.allocator.free(hex);
    try buf.print("{s}\"{s}\": \"{s}\"{s}\n", .{ indent, key, hex, if (comma) "," else "" });
}

fn writeHexArrayField(buf: *Buf, indent: []const u8, key: []const u8, items: []const [32]u8, comma: bool) !void {
    try buf.print("{s}\"{s}\": [", .{ indent, key });
    for (items, 0..) |item, i| {
        if (i > 0) try buf.writeAll(", ");
        const hex = try hexAlloc(buf.allocator, &item);
        defer buf.allocator.free(hex);
        try buf.print("\"{s}\"", .{hex});
    }
    try buf.writeAll(if (comma) "],\n" else "]\n");
}

fn writeStrField(buf: *Buf, indent: []const u8, key: []const u8, s: []const u8, comma: bool) !void {
    try buf.print("{s}\"{s}\": ", .{ indent, key });
    try writeEscapedString(buf, s);
    try buf.writeAll(if (comma) ",\n" else "\n");
}

fn writeStrFieldOpt(buf: *Buf, indent: []const u8, key: []const u8, s: ?[]const u8, comma: bool) !void {
    if (s) |v| {
        try writeStrField(buf, indent, key, v, comma);
    } else {
        try buf.print("{s}\"{s}\": null{s}\n", .{ indent, key, if (comma) "," else "" });
    }
}

fn writeNumField(buf: *Buf, indent: []const u8, key: []const u8, n: anytype, comma: bool) !void {
    try buf.print("{s}\"{s}\": {d}{s}\n", .{ indent, key, n, if (comma) "," else "" });
}

fn writeNumFieldOpt(buf: *Buf, indent: []const u8, key: []const u8, n: anytype, comma: bool) !void {
    if (n) |v| {
        try writeNumField(buf, indent, key, v, comma);
    } else {
        try buf.print("{s}\"{s}\": null{s}\n", .{ indent, key, if (comma) "," else "" });
    }
}

fn writeFloat3Field(buf: *Buf, indent: []const u8, key: []const u8, v: [3]f32, comma: bool) !void {
    try buf.print("{s}\"{s}\": [{d}, {d}, {d}]{s}\n", .{ indent, key, v[0], v[1], v[2], if (comma) "," else "" });
}

fn writeQuaternionField(buf: *Buf, indent: []const u8, key: []const u8, q: v2.Quaternion, comma: bool) !void {
    try buf.print("{s}\"{s}\": {{ \"qx\": {d}, \"qy\": {d}, \"qz\": {d}, \"qw\": {d} }}{s}\n", .{ indent, key, q.qx, q.qy, q.qz, q.qw, if (comma) "," else "" });
}

/// Writes one manifest entry. `value_json` is a pre-built, already-indented
/// JSON object literal (built by the per-fixture `value*` functions below).
/// Asserts the freshly computed blake3 against the `src/golden.zig` constant
/// so this tool can never silently drift from the pinned Zig test — if it
/// fires, `src/golden.zig` and this tool disagree and one of them is wrong.
// ---------------------------------------------------------------------------
// The re-baselined v4 ball.action bytes (Dreamball-y4t.18)
// ---------------------------------------------------------------------------
//
// PINNED, not live-encoded. Produced by crates/identikey-log in the
// identikey-protocol repo, on bc-envelope 0.43.0 / bc-components 0.31.1 /
// dcbor 0.25.2, from the same logical value the Zig `v2.Action` literal in
// `main` describes. Regenerate with:
//
//     cargo run -p identikey-log --example dump_goldens
//
// See the long comment at the v4 block in `main` for why these are pinned and
// what changed. The corresponding pre-Gordian constants still live in
// `src/golden.zig` and are still what the live Zig encoder emits -- this tool
// asserts that, and writes them into each entry's `superseded_*` fields.

/// `200(201(core))` -- a bare Gordian subject. Byte-for-byte identical to the
/// superseded vector from offset 4 onward; only the `81` (array-of-1) is gone.
const GORDIAN_ACTION_V4_UNSIGNED_BYTES_HEX = "d8c8d8c9a763686c63821b0000018bcfe568000764626f647943820102646b696e64781a776f726c64747265652e6b616e62616e2d636172642e6d6f766564747970656b62616c6c2e616374696f6e656163746f7258203b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da296d706172656e742d68617368657381582010101010101010101010101010101010101010101010101010101010101010106e666f726d61742d76657273696f6e04";
/// blake3 of the above == the op's `content_hash`.
const GORDIAN_ACTION_V4_UNSIGNED_BLAKE3 = "cd1afaeec8d6af64b5e1b2e907acbf42ed68316d80e5e430ef3a92e9cbae78c3";
/// `200([200(201(core)), {3: 201(40020([2, sig]))}])` -- the unsigned envelope
/// wrapped, carrying one `'signed'` assertion whose predicate is the known
/// value 3 and whose object is a tagged Ed25519 `Signature`.
const GORDIAN_ACTION_V4_SIGNED_BYTES_HEX = "d8c882d8c8d8c9a763686c63821b0000018bcfe568000764626f647943820102646b696e64781a776f726c64747265652e6b616e62616e2d636172642e6d6f766564747970656b62616c6c2e616374696f6e656163746f7258203b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da296d706172656e742d68617368657381582010101010101010101010101010101010101010101010101010101010101010106e666f726d61742d76657273696f6e04a103d8c9d99c54820258406ce51ce17e05c5db30980200443eade191f3ea4aacf16741c5fba2e3af0349f7dba77a80e74bc3c9a09d9c1dfa23de193366116a8028bc1f737a11caaa460d06";
const GORDIAN_ACTION_V4_SIGNED_BLAKE3 = "28d0cfa146da697b031bf8d414e0eeb0cb0b083a0d86471b1d6b78349753230a";
/// The Ed25519 signature itself: RFC 8032 over the 32-byte SHA-256 digest of
/// the WRAPPED unsigned envelope (not over the canonical bytes, which is what
/// the superseded vector signed).
const GORDIAN_ACTION_V4_SIGNATURE_HEX = "6ce51ce17e05c5db30980200443eade191f3ea4aacf16741c5fba2e3af0349f7dba77a80e74bc3c9a09d9c1dfa23de193366116a8028bc1f737a11caaa460d06";

/// Writes a re-baselined entry: pinned `bytes_hex`/`blake3` plus the
/// `superseded_bytes_hex`/`superseded_blake3` the entry used to carry.
///
/// The superseded values are not a second gate -- nothing compares against
/// them -- they are the audit trail, so a reader can diff the change rather
/// than take "we re-baselined" on faith. Recording them in the entry (not only
/// in prose) also lets a consumer assert it is looking at the post-change
/// manifest.
fn writeRebaselinedEntry(
    allocator: Allocator,
    out: *Buf,
    first: bool,
    name: []const u8,
    wire_type: []const u8,
    format_version: u32,
    value_json: []const u8,
    bytes_hex: []const u8,
    blake3_hex: []const u8,
    superseded_bytes_hex: []const u8,
    superseded_blake3_hex: []const u8,
    note: []const u8,
) !void {
    // Self-check the pin: the declared blake3 must actually be the blake3 of
    // the declared bytes, or the constants above have drifted apart.
    const bytes = try hexDecodeAlloc(allocator, bytes_hex);
    defer allocator.free(bytes);
    const observed = try blake3HexAlloc(allocator, bytes);
    defer allocator.free(observed);
    if (!std.mem.eql(u8, observed, blake3_hex)) {
        std.debug.print(
            "\n  PINNED-CONSTANT DRIFT: {s}\n  observed: {s}\n  declared: {s}\n",
            .{ name, observed, blake3_hex },
        );
        return error.GoldenDrift;
    }

    if (!first) try out.writeAll(",\n");
    try out.writeAll("  {\n");
    try out.print("    \"name\": \"{s}\",\n", .{name});
    try out.print("    \"type\": \"{s}\",\n", .{wire_type});
    try out.print("    \"format_version\": {d},\n", .{format_version});
    try out.writeAll("    \"value\": ");
    try out.writeAll(value_json);
    try out.writeAll(",\n");
    try out.print("    \"bytes_hex\": \"{s}\",\n", .{bytes_hex});
    try out.print("    \"blake3\": \"{s}\",\n", .{blake3_hex});
    try out.print("    \"superseded_bytes_hex\": \"{s}\",\n", .{superseded_bytes_hex});
    try out.print("    \"superseded_blake3\": \"{s}\",\n", .{superseded_blake3_hex});
    try out.writeAll("    \"superseded_by\": \"Dreamball-y4t.16 (decision) / Dreamball-y4t.18 (implementation), 2026-08-07\",\n");
    try out.writeAll("    \"note\": ");
    try writeEscapedString(out, note);
    try out.writeByte('\n');
    try out.writeAll("  }");
}

fn writeEntry(
    allocator: Allocator,
    out: *Buf,
    first: bool,
    name: []const u8,
    wire_type: []const u8,
    format_version: u32,
    value_json: []const u8,
    bytes: []const u8,
    expected_blake3_hex: ?[]const u8,
    note: ?[]const u8,
) !void {
    if (!first) try out.writeAll(",\n");
    const bytes_hex = try hexAlloc(allocator, bytes);
    defer allocator.free(bytes_hex);
    const blake3_hex = try blake3HexAlloc(allocator, bytes);
    defer allocator.free(blake3_hex);

    if (expected_blake3_hex) |exp| {
        if (!std.mem.eql(u8, exp, blake3_hex)) {
            std.debug.print(
                "\n  MANIFEST/GOLDEN.ZIG DRIFT: {s}\n  observed: {s}\n  golden.zig: {s}\n",
                .{ name, blake3_hex, exp },
            );
            return error.GoldenDrift;
        }
    }

    try out.writeAll("  {\n");
    try out.print("    \"name\": \"{s}\",\n", .{name});
    try out.print("    \"type\": \"{s}\",\n", .{wire_type});
    try out.print("    \"format_version\": {d},\n", .{format_version});
    try out.writeAll("    \"value\": ");
    try out.writeAll(value_json);
    try out.writeAll(",\n");
    try out.print("    \"bytes_hex\": \"{s}\",\n", .{bytes_hex});
    try out.print("    \"blake3\": \"{s}\"", .{blake3_hex});
    if (note) |n| {
        try out.writeAll(",\n    \"note\": ");
        try writeEscapedString(out, n);
        try out.writeByte('\n');
    } else {
        try out.writeByte('\n');
    }
    try out.writeAll("  }");
}

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const io = std.Io.Threaded.global_single_threaded.io();

    std.Io.Dir.cwd().createDirPath(io, "fixtures/goldens") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    var out = Buf.init(gpa);
    defer out.deinit();

    try out.writeAll(
        \\{
        \\  "$comment": "CORE REGRESSION GATE. Generated by tools/export-golden-fixtures (zig build export-golden-fixtures). Destined for the Rust IdentiKey core (Dreamball-y4t) -- these ARE the substrate's regression gate; the GoldenDrift self-check in this tool asserts every entry against src/golden.zig before writing. Do not hand-edit -- re-run the generator. NOTE (Dreamball-y4t.18, 2026-08-07): the two v4 ball.action entries were RE-BASELINED onto real Gordian Envelope per the Dreamball-y4t.16 decision; their bytes are pinned hex produced by crates/identikey-log (identikey-protocol), not by the Zig encoder, and each carries superseded_bytes_hex/superseded_blake3 recording what it held before. content_hash changed for every v4 op as a result. Contains ONLY substrate-owned fixtures (ball.dreamball, ball.memory, v4 ball.action). Memory Palace, archiform, and two contested fixtures were partitioned OUT of this file by Dreamball-y4t.11 (per the Dreamball-jie boundary analysis) into fixtures/goldens/palace-manifest.json + palace-v3-manifest.json, fixtures/goldens/archiform-manifest.json, and fixtures/goldens/contested-manifest.json respectively -- none of those three gate the core build. See fixtures/goldens/README.md for the re-baselining posture: a Zig-vs-Rust byte difference here is a QUESTION to investigate, not proof the Zig bytes are authoritative.",
        \\  "entries": [
        \\
    );

    var first = true;

    // ── 1. GOLDEN_ZERO_SEED ──────────────────────────────────────────────────
    {
        const db = protocol.DreamBall{
            .stage = .seed,
            .identity = [_]u8{0} ** 32,
            .genesis_hash = [_]u8{0} ** 32,
            .revision = 0,
        };
        const bytes = try dreamball.envelope.encodeDreamBall(gpa, db);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeStrField(&vbuf, "      ", "stage", "seed", true);
        try writeHexField(&vbuf, "      ", "identity_hex", &db.identity, true);
        try writeHexField(&vbuf, "      ", "genesis_hash_hex", &db.genesis_hash, true);
        try writeNumField(&vbuf, "      ", "revision", db.revision, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "zero_seed", "ball.dreamball", protocol.FORMAT_VERSION, value_json, bytes, golden.GOLDEN_ZERO_SEED_BLAKE3, null);
        first = false;
    }

    // ── 2. GOLDEN_MEMORY_CONNECTION ──────────────────────────────────────────
    {
        const m: protocol.Memory = .{
            .nodes = &.{},
            .connections = &[_]protocol.MemoryConnection{
                .{ .from = 1, .to = 2, .kind = .temporal, .strength = 0.5 },
            },
        };
        const bytes = try dreamball.envelope.encodeMemory(gpa, m);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try vbuf.writeAll("      \"nodes\": [],\n");
        try vbuf.writeAll("      \"connections\": [\n        {\n");
        try writeNumField(&vbuf, "          ", "from", m.connections[0].from, true);
        try writeNumField(&vbuf, "          ", "to", m.connections[0].to, true);
        try writeStrField(&vbuf, "          ", "kind", m.connections[0].kind.toWireString(), true);
        try writeNumField(&vbuf, "          ", "strength", m.connections[0].strength, true);
        try writeStrFieldOpt(&vbuf, "          ", "label", m.connections[0].label, false);
        try vbuf.writeAll("        }\n      ]\n    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "memory_connection", "ball.memory", protocol.FORMAT_VERSION_V2, value_json, bytes, golden.GOLDEN_MEMORY_CONNECTION_BLAKE3, null);
        first = false;
    }

    // GOLDEN_PALACE_FIELD, GOLDEN_LAYOUT, GOLDEN_TIMELINE_{QUIESCENT,CONCURRENT},
    // the v3 GOLDEN_ACTION_* fixtures, GOLDEN_AQUEDUCT, GOLDEN_ELEMENT_TAG,
    // GOLDEN_TRUST_OBSERVATION, GOLDEN_INSCRIPTION, the three GOLDEN_MYTHOS_*
    // fixtures, GOLDEN_ARCHIFORM, and GOLDEN_OBJECT3D used to live here.
    // Dreamball-y4t.11 (2026-08-07) partitioned this core manifest by the
    // Dreamball-jie boundary analysis's four destinations: the Memory Palace
    // v2 fixtures moved to `writePalaceManifest` (palace-manifest.json), the
    // archiform fixtures to `writeArchiformManifest` (archiform-manifest.json),
    // and the two CONTESTED fixtures (layout, trust_observation) to
    // `writeContestedManifest` (contested-manifest.json) rather than being
    // guessed into either bucket. The v3 timeline/action fixtures had already
    // moved earlier (Dreamball-y4t.15) into `writePalaceV3Manifest`
    // (palace-v3-manifest.json). Every move preserved bytes_hex/blake3
    // byte-for-byte; none of those four files gate this core build.

    // ── 19/20. C1 v4 ball.action (unsigned + signed) ────────────────────────
    //
    // RE-BASELINED ONTO REAL GORDIAN ENVELOPE, 2026-08-07 (Dreamball-y4t.16
    // decided it; Dreamball-y4t.18 landed it). These two entries are the only
    // ones in this file whose bytes are NOT what the live Zig encoder emits,
    // and that is deliberate and permanent:
    //
    //   * The Zig `encodeActionV4` implements the pre-Gordian shape --
    //     `200([201(core)])`, attributes as 2-element arrays, raw Ed25519 over
    //     the literal canonical bytes. That shape is NOT Gordian Envelope; it
    //     borrows the #6.200/#6.201 tags and diverges structurally, and
    //     bc-envelope's decoder rejects it outright.
    //   * The substrate now IS Gordian Envelope (crates/identikey-log in the
    //     identikey-protocol repo). Its bytes are `200(201(core))` for a bare
    //     subject, real single-entry-map assertions, `'signed'` as the KNOWN
    //     VALUE 3, and a signature over the wrapped subject's SHA-256 digest
    //     tree -- which is the point, because such a signature SURVIVES
    //     ELISION.
    //   * Rewriting the Zig encoder to emit Gordian bytes is out of scope: the
    //     whole Zig substrate is what the Rust port replaces (epic
    //     Dreamball-y4t). So the new bytes are PINNED HEX here, exactly the
    //     pattern `object3d` and `writeActionV3FixturePinned` already
    //     established for "the live encoder can no longer produce this".
    //
    // What we still do live: run the Zig encoder and assert its output equals
    // the SUPERSEDED constants. That keeps the record of what we moved away
    // from self-checking rather than a copied-out claim, and it keeps
    // `zig build export-golden-fixtures` idempotent and honest -- re-running
    // it can no longer quietly re-assert the old bytes over the new ones.
    {
        const seed: [Ed25519.KeyPair.seed_length]u8 = .{0} ** Ed25519.KeyPair.seed_length;
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);
        const actor = kp.public_key.toBytes();
        const actor_hex = try hexAlloc(gpa, &actor);
        defer gpa.free(actor_hex);
        // The identity is the one thing the re-baselining did NOT move.
        if (!std.mem.eql(u8, golden.GOLDEN_ACTION_V4_ACTOR_HEX, actor_hex)) return error.GoldenDrift;

        var parents = [_][32]u8{[_]u8{0x10} ** 32};
        const body = [_]u8{ 0x82, 0x01, 0x02 }; // canonical CBOR array [1, 2]
        const a = v2.Action{
            .kind = "worldtree.kanban-card.move",
            .parent_hashes = &parents,
            .actor = actor,
            .body = &body,
            .hlc = .{ 1_700_000_000_000, 7 },
        };

        // ---- the superseded (pre-Gordian) bytes, still produced live ------
        const legacy_unsigned = try ev2.encodeActionV4(gpa, a);
        defer gpa.free(legacy_unsigned);
        const legacy_unsigned_hex = try hexAlloc(gpa, legacy_unsigned);
        defer gpa.free(legacy_unsigned_hex);
        if (!std.mem.eql(u8, golden.GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX, legacy_unsigned_hex)) return error.GoldenDrift;
        const legacy_unsigned_blake3 = try blake3HexAlloc(gpa, legacy_unsigned);
        defer gpa.free(legacy_unsigned_blake3);
        if (!std.mem.eql(u8, golden.GOLDEN_ACTION_V4_CONTENT_HASH, legacy_unsigned_blake3)) return error.GoldenDrift;

        const legacy_sig = (try kp.sign(legacy_unsigned, null)).toBytes();
        const legacy_sigs = [_]protocol.Signature{.{ .alg = "ed25519", .value = &legacy_sig }};
        const legacy_signed = try ev2.encodeActionV4Signed(gpa, a, &legacy_sigs);
        defer gpa.free(legacy_signed);
        const legacy_signed_hex = try hexAlloc(gpa, legacy_signed);
        defer gpa.free(legacy_signed_hex);
        if (!std.mem.eql(u8, golden.GOLDEN_ACTION_V4_SIGNED_BYTES_HEX, legacy_signed_hex)) return error.GoldenDrift;
        const legacy_signed_blake3 = try blake3HexAlloc(gpa, legacy_signed);
        defer gpa.free(legacy_signed_blake3);

        const action_v4_note =
            "RE-BASELINED 2026-08-07 onto real Gordian Envelope (bc-envelope 0.43.0), " ++
            "per the Dreamball-y4t.16 decision, landed by Dreamball-y4t.18. The " ++
            "superseded_* fields hold the pre-Gordian values this entry carried " ++
            "before, and the Zig encoder in tools/export-golden-fixtures still " ++
            "produces exactly those, so the record is self-checking rather than " ++
            "copied out. WHAT CHANGED: (1) a subject-only envelope is 200(201(core)), " ++
            "not 200([201(core)]) -- the one-element array is gone, and it is the " ++
            "only difference in the unsigned vector (the core map bytes are " ++
            "byte-identical); (2) attributes are real Gordian assertions -- " ++
            "single-entry maps {predicate: object} -- and 'signed' is the KNOWN " ++
            "VALUE 3, not the text string \"signed\"; (3) the signature is a tagged " ++
            "Signature (#6.40020) over the SHA-256 digest of the WRAPPED unsigned " ++
            "envelope, not raw Ed25519 over the literal canonical bytes. (3) is the " ++
            "reason for the whole change: a signature over a digest tree survives " ++
            "ELISION of an assertion, so a partially redacted op is still verifiable " ++
            "-- see crates/identikey-log/tests/elision.rs in identikey-protocol. " ++
            "CONSEQUENCE: content_hash = blake3(canonical unsigned envelope bytes) " ++
            "changes for every op. UNCHANGED: the logical value, and actor_hex -- " ++
            "the Ed25519 PUBLIC key deterministically derived from the all-zeros " ++
            "32-byte seed (actor_seed_hex) via RFC 8032 keygen, a PUBLIC shared test " ++
            "vector, not a secret. Ed25519 is deterministic and Gordian orders " ++
            "assertions by digest, so any conformant Gordian Envelope implementation " ++
            "must still reproduce these bytes exactly, signature included. These " ++
            "bytes are PINNED HEX: the Zig encoder cannot produce them and will not " ++
            "be taught to, because the Zig substrate is what the Rust port replaces.";

        {
            var vbuf = Buf.init(gpa);
            defer vbuf.deinit();
            try vbuf.writeAll("{\n");
            try writeStrField(&vbuf, "      ", "kind", a.kind, true);
            try writeHexArrayField(&vbuf, "      ", "parent_hashes_hex", &parents, true);
            try writeHexField(&vbuf, "      ", "actor_seed_hex", &seed, true);
            try writeHexField(&vbuf, "      ", "actor_hex", &actor, true);
            try writeHexField(&vbuf, "      ", "body_hex", &body, true);
            try vbuf.print("      \"hlc\": [{d}, {d}],\n", .{ a.hlc[0], a.hlc[1] });
            try writeHexFieldOpt(&vbuf, "      ", "target_fp_hex", null, true);
            try writeNumFieldOpt(&vbuf, "      ", "timestamp", a.timestamp, true);
            try vbuf.writeAll("      \"deps_hex\": [],\n      \"nacks_hex\": []\n    }");
            const value_json = try vbuf.toOwned();
            defer gpa.free(value_json);

            try writeRebaselinedEntry(
                gpa,
                &out,
                first,
                "action_v4_unsigned",
                v2.Action.type_string,
                4,
                value_json,
                GORDIAN_ACTION_V4_UNSIGNED_BYTES_HEX,
                GORDIAN_ACTION_V4_UNSIGNED_BLAKE3,
                legacy_unsigned_hex,
                legacy_unsigned_blake3,
                action_v4_note,
            );
            first = false;
        }

        {
            var vbuf = Buf.init(gpa);
            defer vbuf.deinit();
            try vbuf.writeAll("{\n");
            try writeStrField(&vbuf, "      ", "kind", a.kind, true);
            try writeHexArrayField(&vbuf, "      ", "parent_hashes_hex", &parents, true);
            try writeHexField(&vbuf, "      ", "actor_seed_hex", &seed, true);
            try writeHexField(&vbuf, "      ", "actor_hex", &actor, true);
            try writeHexField(&vbuf, "      ", "body_hex", &body, true);
            try vbuf.print("      \"hlc\": [{d}, {d}],\n", .{ a.hlc[0], a.hlc[1] });
            try vbuf.print(
                "      \"signatures\": [{{ \"alg\": \"ed25519\", \"covers\": \"sha256 digest of the wrapped unsigned envelope\", \"value_hex\": \"{s}\" }}]\n",
                .{GORDIAN_ACTION_V4_SIGNATURE_HEX},
            );
            try vbuf.writeAll("    }");
            const value_json = try vbuf.toOwned();
            defer gpa.free(value_json);

            try writeRebaselinedEntry(
                gpa,
                &out,
                first,
                "action_v4_signed",
                v2.Action.type_string,
                4,
                value_json,
                GORDIAN_ACTION_V4_SIGNED_BYTES_HEX,
                GORDIAN_ACTION_V4_SIGNED_BLAKE3,
                legacy_signed_hex,
                legacy_signed_blake3,
                action_v4_note,
            );
        }
    }

    try out.writeAll("\n  ]\n}\n");

    const manifest = try out.toOwned();
    defer gpa.free(manifest);
    try writeFixture(io, "fixtures/goldens/manifest.json", manifest);

    try writePalaceV3Manifest(gpa, io);
    try writePalaceManifest(gpa, io);
    try writeArchiformManifest(gpa, io);
    try writeContestedManifest(gpa, io);

    const stdout = std.Io.File.stdout();
    var stdout_buf: [512]u8 = undefined;
    var w = stdout.writer(io, &stdout_buf);
    try w.interface.print("export-golden-fixtures: wrote fixtures/goldens/manifest.json (core regression gate)\n", .{});
    try w.interface.print("export-golden-fixtures: wrote fixtures/goldens/palace-v3-manifest.json (not a core gate)\n", .{});
    try w.interface.print("export-golden-fixtures: wrote fixtures/goldens/palace-manifest.json (not a core gate)\n", .{});
    try w.interface.print("export-golden-fixtures: wrote fixtures/goldens/archiform-manifest.json (not a core gate)\n", .{});
    try w.interface.print("export-golden-fixtures: wrote fixtures/goldens/contested-manifest.json (not a core gate; UNRESOLVED destination)\n", .{});
    try w.interface.flush();
}

fn writeHexFieldOpt(buf: *Buf, indent: []const u8, key: []const u8, bytes: ?[]const u8, comma: bool) !void {
    if (bytes) |b| {
        try writeHexField(buf, indent, key, b, comma);
    } else {
        try buf.print("{s}\"{s}\": null{s}\n", .{ indent, key, if (comma) "," else "" });
    }
}

fn writeTimelineFixture(gpa: Allocator, out: *Buf, first: *bool, name: []const u8, heads: [][32]u8, expected_blake3: []const u8) !void {
    const t = v2.Timeline{ .palace_fp = [_]u8{0} ** 32, .head_hashes = heads };
    const bytes = try ev2.encodeTimeline(gpa, t);
    defer gpa.free(bytes);

    var vbuf = Buf.init(gpa);
    defer vbuf.deinit();
    try vbuf.writeAll("{\n");
    try writeHexField(&vbuf, "      ", "palace_fp_hex", &t.palace_fp, true);
    try writeHexArrayField(&vbuf, "      ", "head_hashes_hex", t.head_hashes, true);
    try writeStrFieldOpt(&vbuf, "      ", "note", t.note, false);
    try vbuf.writeAll("    }");
    const value_json = try vbuf.toOwned();
    defer gpa.free(value_json);

    try writeEntry(gpa, out, first.*, name, v2.Timeline.type_string, v2.Timeline.format_version, value_json, bytes, expected_blake3, null);
    first.* = false;
}

/// v3 `ball.action` fixture — PINNED, not live-encoded. Dreamball-y4t.15
/// deleted `ev2.encodeAction` / `v2.ActionKind` (the v3 encoder + closed
/// action-kind palette) from the core substrate, so there is no encoder left
/// in this binary to call. Bytes come straight from the hex this tool wrote
/// the last time a v3 encoder existed (byte-for-byte unchanged), same
/// pattern as the `object3d` fixture above.
fn writeActionV3FixturePinned(
    gpa: Allocator,
    out: *Buf,
    first: *bool,
    name: []const u8,
    action_kind: []const u8,
    actor: [32]u8,
    parent_hashes: []const [32]u8,
    deps: []const [32]u8,
    nacks: []const [32]u8,
    bytes_hex: []const u8,
    expected_blake3: []const u8,
) !void {
    const bytes = try hexDecodeAlloc(gpa, bytes_hex);
    defer gpa.free(bytes);

    var vbuf = Buf.init(gpa);
    defer vbuf.deinit();
    try vbuf.writeAll("{\n");
    try writeStrField(&vbuf, "      ", "action_kind", action_kind, true);
    try writeHexField(&vbuf, "      ", "actor_hex", &actor, true);
    try writeHexArrayField(&vbuf, "      ", "parent_hashes_hex", parent_hashes, true);
    try writeHexArrayField(&vbuf, "      ", "deps_hex", deps, true);
    try writeHexArrayField(&vbuf, "      ", "nacks_hex", nacks, true);
    try writeHexFieldOpt(&vbuf, "      ", "target_fp_hex", null, true);
    try writeNumFieldOpt(&vbuf, "      ", "timestamp", @as(?i64, null), false);
    try vbuf.writeAll("    }");
    const value_json = try vbuf.toOwned();
    defer gpa.free(value_json);

    try writeEntry(gpa, out, first.*, name, "ball.action", 3, value_json, bytes, expected_blake3, "This is the LEGACY v3 palace-profile encoder (closed action-kind key, format-version pinned to the literal 3), preserved verbatim for the Memory Palace extraction (Dreamball-etk). The core substrate dropped v3 ball.action support (Dreamball-y4t.15); these bytes are pinned hex, not live-encoded, because the encoder no longer exists in this binary.");
    first.* = false;
}

/// Writes fixtures/goldens/palace-v3-manifest.json — the 5 palace-profile
/// fixtures (v3 ball.action x3, ball.timeline x2) that Dreamball-y4t.15
/// removed from the core regression gate (manifest.json) when v3
/// `ball.action` was dropped from the substrate. This file is NOT a core
/// gate: nothing in `zig build test` / `zig build export-golden-fixtures`
/// treats a diff here as a failure. It exists so the Memory Palace
/// extraction (Dreamball-etk) can pick up these fixtures unchanged — the
/// bytes and hashes are byte-for-byte identical to what manifest.json used
/// to carry under these names.
fn writePalaceV3Manifest(gpa: Allocator, io: std.Io) !void {
    var out = Buf.init(gpa);
    defer out.deinit();

    try out.writeAll(
        \\{
        \\  "$comment": "RETAINED, NOT A CORE GATE. Dreamball-y4t.15 (2026-08-07) dropped format_version 3 ball.action support from the core substrate -- ActionKind and the v3 encoder were deleted from src/protocol_v2.zig / src/envelope_v2.zig. These 5 fixtures (the closed v3 palace-action profile + the palace-profile ball.timeline entries) are preserved here VERBATIM -- same bytes_hex/blake3 they had in fixtures/goldens/manifest.json before the split -- for the Memory Palace extraction (Dreamball-etk) to pick up unchanged. Nothing in the core build treats a diff in this file as a failure; it is not regenerated from a live encoder (see tools/export-golden-fixtures/main.zig writeActionV3FixturePinned).",
        \\  "entries": [
        \\
    );

    var first = true;

    var heads1 = [_][32]u8{[_]u8{0xAA} ** 32};
    try writeTimelineFixture(gpa, &out, &first, "timeline_quiescent", &heads1, golden.GOLDEN_TIMELINE_QUIESCENT_BLAKE3);

    var heads2 = [_][32]u8{ [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 32 };
    try writeTimelineFixture(gpa, &out, &first, "timeline_concurrent", &heads2, golden.GOLDEN_TIMELINE_CONCURRENT_BLAKE3);

    try writeActionV3FixturePinned(
        gpa,
        &out,
        &first,
        "action_v3_single_parent",
        "palace-minted",
        [_]u8{0x01} ** 32,
        &[_][32]u8{[_]u8{0x10} ** 32},
        &[_][32]u8{},
        &[_][32]u8{},
        "d8c881d8c9a564747970656b62616c6c2e616374696f6e656163746f72582001010101010101010101010101010101010101010101010101010101010101016b616374696f6e2d6b696e646d70616c6163652d6d696e7465646d706172656e742d68617368657381582010101010101010101010101010101010101010101010101010101010101010106e666f726d61742d76657273696f6e03",
        "b28b972de27f857670b5bafc782c7a635fca34e5170026573b3ed4aa150ef26b",
    );

    try writeActionV3FixturePinned(
        gpa,
        &out,
        &first,
        "action_v3_multi_parent",
        "move",
        [_]u8{0x01} ** 32,
        &[_][32]u8{ [_]u8{0x10} ** 32, [_]u8{0x11} ** 32 },
        &[_][32]u8{},
        &[_][32]u8{},
        "d8c881d8c9a564747970656b62616c6c2e616374696f6e656163746f72582001010101010101010101010101010101010101010101010101010101010101016b616374696f6e2d6b696e64646d6f76656d706172656e742d6861736865738258201010101010101010101010101010101010101010101010101010101010101010582011111111111111111111111111111111111111111111111111111111111111116e666f726d61742d76657273696f6e03",
        "a28288920342400cf68370092a913e0602ed3fb667c210be6e2549f76250d3c8",
    );

    try writeActionV3FixturePinned(
        gpa,
        &out,
        &first,
        "action_v3_deps_nacks",
        "inscription-updated",
        [_]u8{0x01} ** 32,
        &[_][32]u8{[_]u8{0x10} ** 32},
        &[_][32]u8{[_]u8{0x20} ** 32},
        &[_][32]u8{[_]u8{0x30} ** 32},
        "d8c883d8c9a564747970656b62616c6c2e616374696f6e656163746f72582001010101010101010101010101010101010101010101010101010101010101016b616374696f6e2d6b696e6473696e736372697074696f6e2d757064617465646d706172656e742d68617368657381582010101010101010101010101010101010101010101010101010101010101010106e666f726d61742d76657273696f6e038264646570735820202020202020202020202020202020202020202020202020202020202020202082656e61636b7358203030303030303030303030303030303030303030303030303030303030303030",
        "ea5fb1e975dcd9d3c229cfad27735bd3ab95751f29273284f4678098016bb619",
    );

    try out.writeAll("\n  ]\n}\n");

    const manifest = try out.toOwned();
    defer gpa.free(manifest);
    try writeFixture(io, "fixtures/goldens/palace-v3-manifest.json", manifest);
}

/// Writes fixtures/goldens/palace-manifest.json — the 7 v2-format-version
/// Memory Palace domain fixtures (palace_field, aqueduct, element_tag,
/// inscription, the three mythos vectors) partitioned OUT of manifest.json
/// by Dreamball-y4t.11, per the Dreamball-jie boundary analysis's
/// destination for the memory-palace repo (Dreamball-etk). This file is NOT
/// a core gate: nothing in `zig build test` / `zig build export-golden-
/// fixtures` treats a diff here as a failure. It complements
/// fixtures/goldens/palace-v3-manifest.json (which Dreamball-y4t.15 wrote
/// earlier for the v3-format-version palace fixtures) — together the two
/// files are the full Memory Palace golden set. Every value/bytes_hex/blake3
/// below is byte-for-byte identical to what manifest.json used to carry
/// under these names.
fn writePalaceManifest(gpa: Allocator, io: std.Io) !void {
    var out = Buf.init(gpa);
    defer out.deinit();

    try out.writeAll(
        \\{
        \\  "$comment": "NOT A CORE GATE. Destined for the memory-palace repo (Dreamball-etk). Contains the v2-format-version Memory Palace domain fixtures (ball.dreamball.field, ball.aqueduct, ball.element-tag, ball.inscription, ball.mythos x3) partitioned out of fixtures/goldens/manifest.json by Dreamball-y4t.11, per the Dreamball-jie boundary analysis -- byte-for-byte identical to their prior manifest.json entries. See also fixtures/goldens/palace-v3-manifest.json for the v3-format-version palace fixtures (ball.timeline, legacy ball.action v3) moved out earlier by Dreamball-y4t.15; together the two files are the full Memory Palace golden set. Nothing in the core build treats a diff in this file as a failure.",
        \\  "entries": [
        \\
    );

    var first = true;

    // GOLDEN_PALACE_FIELD — built directly with zbor/dcbor primitives (same
    // as the golden.zig test) because protocol.DreamBall has no field_kind
    // slot -- it is an attribute-level addition per PROTOCOL.md §13.1.
    {
        var ai = std.Io.Writer.Allocating.init(gpa);
        defer ai.deinit();
        const w = &ai.writer;
        try zbor.builder.writeTag(w, dcbor.Tag.envelope);
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTag(w, dcbor.Tag.leaf);
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
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "field-kind");
        try zbor.builder.writeTextString(w, "palace");
        const bytes = try ai.toOwnedSlice();
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeStrField(&vbuf, "      ", "stage", "seed", true);
        try writeHexField(&vbuf, "      ", "identity_hex", &([_]u8{0} ** 32), true);
        try writeHexField(&vbuf, "      ", "genesis_hash_hex", &([_]u8{0} ** 32), true);
        try writeNumField(&vbuf, "      ", "revision", @as(u32, 0), true);
        try vbuf.writeAll("      \"attributes\": [[\"field-kind\", \"palace\"]]\n    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "palace_field", "ball.dreamball.field", 2, value_json, bytes, golden.GOLDEN_PALACE_FIELD_BLAKE3, "Attribute-level fixture: ball.dreamball.field carries no dedicated field-kind slot on protocol.DreamBall, so this fixture is a bare core map + one ['field-kind','palace'] attribute, not a protocol.DreamBall struct literal.");
        first = false;
    }

    // GOLDEN_AQUEDUCT
    {
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
        const bytes = try ev2.encodeAqueduct(gpa, aq);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeHexField(&vbuf, "      ", "from_hex", &aq.from, true);
        try writeHexField(&vbuf, "      ", "to_hex", &aq.to, true);
        try writeStrField(&vbuf, "      ", "kind", aq.kind, true);
        try writeNumField(&vbuf, "      ", "capacity", aq.capacity, true);
        try writeNumField(&vbuf, "      ", "strength", aq.strength, true);
        try writeNumField(&vbuf, "      ", "resistance", aq.resistance, true);
        try writeNumField(&vbuf, "      ", "capacitance", aq.capacitance, true);
        try writeNumFieldOpt(&vbuf, "      ", "conductance", aq.conductance, true);
        try writeStrFieldOpt(&vbuf, "      ", "phase", if (aq.phase) |ph| ph.toWireString() else null, true);
        try writeNumFieldOpt(&vbuf, "      ", "last_traversed", aq.last_traversed, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "aqueduct", v2.Aqueduct.type_string, v2.Aqueduct.format_version, value_json, bytes, golden.GOLDEN_AQUEDUCT_BLAKE3, null);
        first = false;
    }

    // GOLDEN_ELEMENT_TAG
    {
        const et = v2.ElementTag{ .element = "fire", .phase = "yang" };
        const bytes = try ev2.encodeElementTag(gpa, et);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeStrField(&vbuf, "      ", "element", et.element, true);
        try writeStrFieldOpt(&vbuf, "      ", "phase", et.phase, true);
        try writeStrFieldOpt(&vbuf, "      ", "note", et.note, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "element_tag", v2.ElementTag.type_string, v2.ElementTag.format_version, value_json, bytes, golden.GOLDEN_ELEMENT_TAG_BLAKE3, null);
        first = false;
    }

    // GOLDEN_INSCRIPTION
    {
        const ins = v2.Inscription{ .surface = "scroll", .placement = "curator", .note = "# Hello\n\nA short markdown inscription." };
        const bytes = try ev2.encodeInscription(gpa, ins);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeStrField(&vbuf, "      ", "surface", ins.surface, true);
        try writeStrField(&vbuf, "      ", "placement", ins.placement, true);
        try writeStrFieldOpt(&vbuf, "      ", "note", ins.note, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "inscription", v2.Inscription.type_string, v2.Inscription.format_version, value_json, bytes, golden.GOLDEN_INSCRIPTION_BLAKE3, null);
        first = false;
    }

    // GOLDEN_MYTHOS_{CANONICAL_GENESIS,CANONICAL_SUCCESSOR,POETIC}
    {
        try writeMythosFixture(gpa, &out, &first, "mythos_canonical_genesis", .{
            .is_genesis = true,
            .discovered_in = [_]u8{0xCC} ** 32,
            .true_name = "The Palace of Remembered Light",
            .authored_at = 1_700_000_000,
        }, golden.GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3);

        var syn = [_][32]u8{[_]u8{0xDD} ** 32};
        try writeMythosFixture(gpa, &out, &first, "mythos_canonical_successor", .{
            .is_genesis = false,
            .predecessor = [_]u8{0xCC} ** 32,
            .synthesizes = &syn,
            .discovered_in = [_]u8{0xEE} ** 32,
            .true_name = "The Forge of Quiet Thunder",
            .authored_at = 1_700_000_001,
        }, golden.GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3);

        try writeMythosFixture(gpa, &out, &first, "mythos_poetic", .{
            .is_genesis = true,
            .about = [_]u8{0x05} ** 32,
            .form = "invocation",
            .body = "In the palace of stars, the dreamer wakes.",
            .author = [_]u8{0x01} ** 32,
            .authored_at = 1_700_000_002,
        }, golden.GOLDEN_MYTHOS_POETIC_BLAKE3);
    }

    try out.writeAll("\n  ]\n}\n");

    const manifest = try out.toOwned();
    defer gpa.free(manifest);
    try writeFixture(io, "fixtures/goldens/palace-manifest.json", manifest);
}

/// Writes fixtures/goldens/archiform-manifest.json — the 2 fixtures
/// (archiform, object3d) partitioned OUT of manifest.json by
/// Dreamball-y4t.11, per the Dreamball-jie boundary analysis's destination
/// for the archiform repo (Dreamball-h7s). NOT a core gate. object3d's live
/// Zig encoder was already deleted (Dreamball-h7s.1: it only demoed the
/// dissolved Zig-canonical authoring pipeline), so its bytes are pinned hex,
/// not live-encoded, same pattern as the v3 action fixtures in
/// `writeActionV3FixturePinned`. Both entries are byte-for-byte identical to
/// their prior manifest.json entries.
fn writeArchiformManifest(gpa: Allocator, io: std.Io) !void {
    var out = Buf.init(gpa);
    defer out.deinit();

    try out.writeAll(
        \\{
        \\  "$comment": "NOT A CORE GATE. Destined for the archiform repo (Dreamball-h7s). Contains ball.archiform and ball.object3d, partitioned out of fixtures/goldens/manifest.json by Dreamball-y4t.11, per the Dreamball-jie boundary analysis -- byte-for-byte identical to their prior manifest.json entries. object3d's live Zig encoder was already deleted (Dreamball-h7s.1: it only demoed the dissolved Zig-canonical authoring pipeline); its bytes here are pinned hex, not live-encoded. Nothing in the core build treats a diff in this file as a failure.",
        \\  "entries": [
        \\
    );

    var first = true;

    // GOLDEN_ARCHIFORM
    {
        const ar = v2.Archiform{ .form = "library", .tradition = "hermetic", .parent_form = "forge" };
        const bytes = try ev2.encodeArchiform(gpa, ar);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeStrField(&vbuf, "      ", "form", ar.form, true);
        try writeStrFieldOpt(&vbuf, "      ", "tradition", ar.tradition, true);
        try writeStrFieldOpt(&vbuf, "      ", "parent_form", ar.parent_form, true);
        try writeStrFieldOpt(&vbuf, "      ", "note", ar.note, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "archiform", v2.Archiform.type_string, v2.Archiform.format_version, value_json, bytes, golden.GOLDEN_ARCHIFORM_BLAKE3, null);
        first = false;
    }

    // GOLDEN_OBJECT3D — pinned hex, see doc comment above.
    {
        const bytes = try hexDecodeAlloc(gpa, golden.GOLDEN_OBJECT3D_BYTES_HEX);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeStrField(&vbuf, "      ", "mesh", "glb:tree-01", true);
        try writeFloat3Field(&vbuf, "      ", "position", .{ 1.0, 2.0, 3.0 }, true);
        try writeQuaternionField(&vbuf, "      ", "rotation", .{ .qx = 0, .qy = 0, .qz = 0, .qw = 1 }, true);
        try writeFloat3Field(&vbuf, "      ", "scale", .{ 1.0, 1.0, 1.0 }, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "object3d", "ball.object3d", 2, value_json, bytes, golden.GOLDEN_OBJECT3D_BLAKE3, null);
        first = false;
    }

    try out.writeAll("\n  ]\n}\n");

    const manifest = try out.toOwned();
    defer gpa.free(manifest);
    try writeFixture(io, "fixtures/goldens/archiform-manifest.json", manifest);
}

/// Writes fixtures/goldens/contested-manifest.json — the 2 fixtures (layout,
/// trust_observation) the Dreamball-jie boundary analysis explicitly left
/// CONTESTED rather than assigning to core, archiform, or memory-palace.
/// Dreamball-y4t.11 partitions them into their OWN file, deliberately, so
/// that filing them into either the archiform or palace manifest does not
/// silently resolve a call the architect analysis flagged as undecided. See
/// the file's own header for the specific arguments on each side. NOT a
/// core gate. Both entries are byte-for-byte identical to their prior
/// manifest.json entries.
fn writeContestedManifest(gpa: Allocator, io: std.Io) !void {
    var out = Buf.init(gpa);
    defer out.deinit();

    try out.writeAll(
        \\{
        \\  "$comment": "UNRESOLVED -- placement here is NOT a decision. Contains ball.layout and ball.trust-observation, the two fixtures the Dreamball-jie boundary analysis explicitly left CONTESTED rather than assigning to a destination: (1) layout -- argued to be generic spatial composition, i.e. archiform's concern, not core's and not the memory-palace's, but not yet adopted by any boundary ADR; (2) trust_observation -- argued to be an identity-layer concern that should be OFFERED to identikey-protocol rather than assumed into the memory-palace. Dreamball-y4t.11 partitioned these two out of fixtures/goldens/manifest.json into this dedicated file, byte-for-byte identical to their prior manifest.json entries, specifically so neither call gets silently resolved by filing them into archiform-manifest.json or palace-manifest.json. Nothing in the core build treats a diff in this file as a failure. Whoever adopts the boundary ADR should move these entries to their real destination and delete this file.",
        \\  "entries": [
        \\
    );

    var first = true;

    // GOLDEN_LAYOUT
    {
        const l = v2.Layout{
            .placements = &[_]v2.Placement{
                .{ .child_fp = [_]u8{0x01} ** 32, .position = .{ 0.0, 0.0, 0.0 }, .facing = .{ .qx = 0.0, .qy = 0.0, .qz = 0.0, .qw = 1.0 } },
                .{ .child_fp = [_]u8{0x02} ** 32, .position = .{ 1.0, 0.0, 0.0 }, .facing = .{ .qx = 0.0, .qy = 0.0, .qz = 0.0, .qw = 1.0 } },
            },
        };
        const bytes = try ev2.encodeLayout(gpa, l);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n      \"placements\": [\n");
        for (l.placements, 0..) |p, i| {
            try vbuf.writeAll("        {\n");
            try writeHexField(&vbuf, "          ", "child_fp_hex", &p.child_fp, true);
            try writeFloat3Field(&vbuf, "          ", "position", p.position, true);
            try writeQuaternionField(&vbuf, "          ", "facing", p.facing, false);
            try vbuf.print("        }}{s}\n", .{if (i + 1 < l.placements.len) "," else ""});
        }
        try vbuf.writeAll("      ],\n");
        try writeStrFieldOpt(&vbuf, "      ", "note", l.note, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "layout", v2.Layout.type_string, v2.Layout.format_version, value_json, bytes, golden.GOLDEN_LAYOUT_BLAKE3, null);
        first = false;
    }

    // GOLDEN_TRUST_OBSERVATION
    {
        const axes = [_]v2.TrustAxis{
            .{ .name = "reliability", .value = 0.8, .range = .{ 0.0, 1.0 } },
            .{ .name = "alignment", .value = 0.6, .range = .{ 0.0, 1.0 } },
        };
        const sig1_val = [_]u8{0xAA} ** 64;
        const sig2_val = [_]u8{0xBB} ** 64;
        const sigs = [_]protocol.Signature{
            .{ .alg = "ed25519", .value = &sig1_val },
            .{ .alg = "ed25519", .value = &sig2_val },
        };
        const to = v2.TrustObservation{
            .observer = [_]u8{0x01} ** 32,
            .about = [_]u8{0x02} ** 32,
            .axes = &axes,
            .signatures = &sigs,
        };
        const bytes = try ev2.encodeTrustObservation(gpa, to);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeHexField(&vbuf, "      ", "observer_hex", &to.observer, true);
        try writeHexField(&vbuf, "      ", "about_hex", &to.about, true);
        try vbuf.writeAll("      \"axes\": [\n");
        for (to.axes, 0..) |ax, i| {
            try vbuf.writeAll("        {\n");
            try writeStrField(&vbuf, "          ", "name", ax.name, true);
            try writeNumField(&vbuf, "          ", "value", ax.value, true);
            try vbuf.print("          \"range\": [{d}, {d}]\n", .{ ax.range[0], ax.range[1] });
            try vbuf.print("        }}{s}\n", .{if (i + 1 < to.axes.len) "," else ""});
        }
        try vbuf.writeAll("      ],\n");
        try writeNumFieldOpt(&vbuf, "      ", "observed_at", to.observed_at, true);
        try writeStrFieldOpt(&vbuf, "      ", "context", to.context, true);
        try vbuf.writeAll("      \"signatures\": [\n");
        for (to.signatures, 0..) |sig, i| {
            try vbuf.writeAll("        {\n");
            try writeStrField(&vbuf, "          ", "alg", sig.alg, true);
            try writeHexField(&vbuf, "          ", "value_hex", sig.value, false);
            try vbuf.print("        }}{s}\n", .{if (i + 1 < to.signatures.len) "," else ""});
        }
        try vbuf.writeAll("      ]\n    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "trust_observation", v2.TrustObservation.type_string, v2.TrustObservation.format_version, value_json, bytes, golden.GOLDEN_TRUST_OBSERVATION_BLAKE3, "Signature bytes (0xAA*64, 0xBB*64) are constant filler used to exercise the signatures[] slot -- not real Ed25519 signatures.");
        first = false;
    }

    try out.writeAll("\n  ]\n}\n");

    const manifest = try out.toOwned();
    defer gpa.free(manifest);
    try writeFixture(io, "fixtures/goldens/contested-manifest.json", manifest);
}

fn writeMythosFixture(gpa: Allocator, out: *Buf, first: *bool, name: []const u8, m: v2.Mythos, expected_blake3: []const u8) !void {
    const bytes = try ev2.encodeMythos(gpa, m);
    defer gpa.free(bytes);

    var vbuf = Buf.init(gpa);
    defer vbuf.deinit();
    try vbuf.writeAll("{\n");
    try vbuf.print("      \"is_genesis\": {},\n", .{m.is_genesis});
    try writeHexFieldOpt(&vbuf, "      ", "predecessor_hex", if (m.predecessor) |p| &p else null, true);
    try writeHexFieldOpt(&vbuf, "      ", "about_hex", if (m.about) |a| &a else null, true);
    try writeStrFieldOpt(&vbuf, "      ", "form", m.form, true);
    try writeStrFieldOpt(&vbuf, "      ", "body", m.body, true);
    try writeStrFieldOpt(&vbuf, "      ", "true_name", m.true_name, true);
    try writeHexFieldOpt(&vbuf, "      ", "discovered_in_hex", if (m.discovered_in) |d| &d else null, true);
    try writeHexArrayField(&vbuf, "      ", "synthesizes_hex", m.synthesizes, true);
    try writeHexArrayField(&vbuf, "      ", "inspired_by_hex", m.inspired_by, true);
    try writeHexFieldOpt(&vbuf, "      ", "author_hex", if (m.author) |a| &a else null, true);
    try writeNumFieldOpt(&vbuf, "      ", "authored_at", m.authored_at, false);
    try vbuf.writeAll("    }");
    const value_json = try vbuf.toOwned();
    defer gpa.free(value_json);

    try writeEntry(gpa, out, first.*, name, v2.Mythos.type_string, v2.Mythos.format_version, value_json, bytes, expected_blake3, null);
    first.* = false;
}

fn hexDecodeAlloc(allocator: Allocator, hex: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, hex.len / 2);
    _ = try std.fmt.hexToBytes(out, hex);
    return out;
}

fn writeFixture(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var w = file.writer(io, &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}
