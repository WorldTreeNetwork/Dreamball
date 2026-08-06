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
        \\  "$comment": "Generated by tools/export-golden-fixtures (zig build export-golden-fixtures). Do not hand-edit -- re-run the generator. See fixtures/goldens/README.md for the re-baselining posture: a Zig-vs-Rust byte difference here is a QUESTION to investigate, not proof the Zig bytes are authoritative.",
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

    // ── 3. GOLDEN_PALACE_FIELD ───────────────────────────────────────────────
    // Built directly with zbor/dcbor primitives (same as the golden.zig test)
    // because protocol.DreamBall has no field_kind slot -- it is an
    // attribute-level addition per PROTOCOL.md §13.1.
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

    // ── 4. GOLDEN_LAYOUT ─────────────────────────────────────────────────────
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

    // ── 5/6. GOLDEN_TIMELINE_{QUIESCENT,CONCURRENT} ─────────────────────────
    {
        var heads1 = [_][32]u8{[_]u8{0xAA} ** 32};
        try writeTimelineFixture(gpa, &out, &first, "timeline_quiescent", &heads1, golden.GOLDEN_TIMELINE_QUIESCENT_BLAKE3);

        var heads2 = [_][32]u8{ [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 32 };
        try writeTimelineFixture(gpa, &out, &first, "timeline_concurrent", &heads2, golden.GOLDEN_TIMELINE_CONCURRENT_BLAKE3);
    }

    // ── 7/8/9. v3 GOLDEN_ACTION_{SINGLE_PARENT,MULTI_PARENT,DEPS_NACKS} ─────
    {
        var p1 = [_][32]u8{[_]u8{0x10} ** 32};
        try writeActionV3Fixture(gpa, &out, &first, "action_v3_single_parent", .{
            .kind = v2.ActionKind.palace_minted.toWireString(),
            .actor = [_]u8{0x01} ** 32,
            .parent_hashes = &p1,
            .hlc = .{ 0, 0 },
        }, golden.GOLDEN_ACTION_SINGLE_PARENT_BLAKE3);

        var p2 = [_][32]u8{ [_]u8{0x10} ** 32, [_]u8{0x11} ** 32 };
        try writeActionV3Fixture(gpa, &out, &first, "action_v3_multi_parent", .{
            .kind = v2.ActionKind.move.toWireString(),
            .actor = [_]u8{0x01} ** 32,
            .parent_hashes = &p2,
            .hlc = .{ 0, 0 },
        }, golden.GOLDEN_ACTION_MULTI_PARENT_BLAKE3);

        var p3 = [_][32]u8{[_]u8{0x10} ** 32};
        var deps = [_]v2.ActionRef{[_]u8{0x20} ** 32};
        var nacks = [_]v2.ActionRef{[_]u8{0x30} ** 32};
        try writeActionV3Fixture(gpa, &out, &first, "action_v3_deps_nacks", .{
            .kind = v2.ActionKind.inscription_updated.toWireString(),
            .actor = [_]u8{0x01} ** 32,
            .parent_hashes = &p3,
            .hlc = .{ 0, 0 },
            .deps = &deps,
            .nacks = &nacks,
        }, golden.GOLDEN_ACTION_DEPS_NACKS_BLAKE3);
    }

    // ── 10. GOLDEN_AQUEDUCT ──────────────────────────────────────────────────
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

    // ── 11. GOLDEN_ELEMENT_TAG ───────────────────────────────────────────────
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

    // ── 12. GOLDEN_TRUST_OBSERVATION ─────────────────────────────────────────
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

    // ── 13. GOLDEN_INSCRIPTION ───────────────────────────────────────────────
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

    // ── 14/15/16. GOLDEN_MYTHOS_{CANONICAL_GENESIS,CANONICAL_SUCCESSOR,POETIC} ──
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

    // ── 17. GOLDEN_ARCHIFORM ─────────────────────────────────────────────────
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

    // ── 18. GOLDEN_OBJECT3D ──────────────────────────────────────────────────
    {
        const o = v2.Object3d{
            .mesh = "glb:tree-01",
            .position = .{ 1.0, 2.0, 3.0 },
            .rotation = .{ .qx = 0, .qy = 0, .qz = 0, .qw = 1 },
            .scale = .{ 1.0, 1.0, 1.0 },
        };
        const bytes = try ev2.encodeObject3d(gpa, o);
        defer gpa.free(bytes);

        var vbuf = Buf.init(gpa);
        defer vbuf.deinit();
        try vbuf.writeAll("{\n");
        try writeStrField(&vbuf, "      ", "mesh", o.mesh, true);
        try writeFloat3Field(&vbuf, "      ", "position", o.position, true);
        try writeQuaternionField(&vbuf, "      ", "rotation", o.rotation, true);
        try writeFloat3Field(&vbuf, "      ", "scale", o.scale, false);
        try vbuf.writeAll("    }");
        const value_json = try vbuf.toOwned();
        defer gpa.free(value_json);

        try writeEntry(gpa, &out, first, "object3d", v2.Object3d.type_string, v2.Object3d.format_version, value_json, bytes, golden.GOLDEN_OBJECT3D_BLAKE3, null);
        first = false;

        // The struct-literal fixture must also match the historically pinned
        // full-bytes hex constant (golden.zig locks both the bytes AND the hash).
        const expected_bytes = try hexDecodeAlloc(gpa, golden.GOLDEN_OBJECT3D_BYTES_HEX);
        defer gpa.free(expected_bytes);
        if (!std.mem.eql(u8, bytes, expected_bytes)) return error.GoldenDrift;
    }

    // ── 19/20. C1 v4 ball.action (unsigned + signed) ────────────────────────
    {
        const seed: [Ed25519.KeyPair.seed_length]u8 = .{0} ** Ed25519.KeyPair.seed_length;
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);
        const actor = kp.public_key.toBytes();
        const actor_hex = try hexAlloc(gpa, &actor);
        defer gpa.free(actor_hex);
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

        const unsigned = try ev2.encodeActionV4(gpa, a);
        defer gpa.free(unsigned);

        const action_v4_note =
            "actor is the Ed25519 PUBLIC key deterministically derived from the " ++
            "all-zeros 32-byte seed (actor_seed_hex) via RFC 8032 keygen -- a " ++
            "PUBLIC, shared test vector, not a secret. Any RFC-8032-compliant " ++
            "implementation (including bc-envelope's Rust Ed25519 stack) must " ++
            "re-derive the identical actor and, for the signed variant, the " ++
            "identical deterministic signature over the unsigned bytes.";

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

            // encodeActionV4's golden.zig pin is the FULL BYTES constant
            // (GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX), not a blake3 -- verified
            // against that constant (and the content_hash) just below, so no
            // blake3 cross-check is passed to writeEntry here.
            try writeEntry(gpa, &out, first, "action_v4_unsigned", v2.Action.type_string, 4, value_json, unsigned, null, action_v4_note);
            first = false;

            const expected_unsigned = try hexDecodeAlloc(gpa, golden.GOLDEN_ACTION_V4_UNSIGNED_BYTES_HEX);
            defer gpa.free(expected_unsigned);
            if (!std.mem.eql(u8, unsigned, expected_unsigned)) return error.GoldenDrift;
            var ch: [32]u8 = undefined;
            std.crypto.hash.Blake3.hash(unsigned, &ch, .{});
            const ch_hex = try hexAlloc(gpa, &ch);
            defer gpa.free(ch_hex);
            if (!std.mem.eql(u8, golden.GOLDEN_ACTION_V4_CONTENT_HASH, ch_hex)) return error.GoldenDrift;
        }

        const sig = (try kp.sign(unsigned, null)).toBytes();
        const sigs = [_]protocol.Signature{.{ .alg = "ed25519", .value = &sig }};
        const signed = try ev2.encodeActionV4Signed(gpa, a, &sigs);
        defer gpa.free(signed);

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
            try vbuf.writeAll("      \"signatures\": [{ \"alg\": \"ed25519\", \"value_hex\": \"");
            const sig_hex = try hexAlloc(gpa, &sig);
            defer gpa.free(sig_hex);
            try vbuf.print("{s}\" }}]\n", .{sig_hex});
            try vbuf.writeAll("    }");
            const value_json = try vbuf.toOwned();
            defer gpa.free(value_json);

            try writeEntry(gpa, &out, first, "action_v4_signed", v2.Action.type_string, 4, value_json, signed, null, action_v4_note);

            const expected_signed = try hexDecodeAlloc(gpa, golden.GOLDEN_ACTION_V4_SIGNED_BYTES_HEX);
            defer gpa.free(expected_signed);
            if (!std.mem.eql(u8, signed, expected_signed)) return error.GoldenDrift;
        }
    }

    try out.writeAll("\n  ]\n}\n");

    const manifest = try out.toOwned();
    defer gpa.free(manifest);
    try writeFixture(io, "fixtures/goldens/manifest.json", manifest);

    const stdout = std.Io.File.stdout();
    var stdout_buf: [512]u8 = undefined;
    var w = stdout.writer(io, &stdout_buf);
    try w.interface.print("export-golden-fixtures: wrote fixtures/goldens/manifest.json\n", .{});
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

fn writeActionV3Fixture(gpa: Allocator, out: *Buf, first: *bool, name: []const u8, a: v2.Action, expected_blake3: []const u8) !void {
    const bytes = try ev2.encodeAction(gpa, a);
    defer gpa.free(bytes);

    var vbuf = Buf.init(gpa);
    defer vbuf.deinit();
    try vbuf.writeAll("{\n");
    try writeStrField(&vbuf, "      ", "action_kind", a.kind, true);
    try writeHexField(&vbuf, "      ", "actor_hex", &a.actor, true);
    try writeHexArrayField(&vbuf, "      ", "parent_hashes_hex", a.parent_hashes, true);
    try writeHexArrayField(&vbuf, "      ", "deps_hex", a.deps, true);
    try writeHexArrayField(&vbuf, "      ", "nacks_hex", a.nacks, true);
    try writeHexFieldOpt(&vbuf, "      ", "target_fp_hex", if (a.target_fp) |tfp| &tfp else null, true);
    try writeNumFieldOpt(&vbuf, "      ", "timestamp", a.timestamp, false);
    try vbuf.writeAll("    }");
    const value_json = try vbuf.toOwned();
    defer gpa.free(value_json);

    try writeEntry(gpa, out, first.*, name, "ball.action", 3, value_json, bytes, expected_blake3, "This is the LEGACY v3 palace-profile encoder (closed action-kind key, format-version pinned to the literal 3) -- distinct from the v4 open-kind encoder used by action_v4_unsigned/action_v4_signed below. See src/envelope_v2.zig encodeAction's doc comment.");
    first.* = false;
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
