//! export-envelope-fixtures — writes fixtures/envelope_golden/<type>.cbor
//!
//! Encodes one representative instance of each of the 9 palace envelope types
//! using the same inputs as the golden-bytes tests in src/golden.zig, producing
//! stable CBOR byte files that the Vitest round-trip tests can consume.
//!
//! Run via:
//!   zig build export-envelope-fixtures
//!
//! Output files (under fixtures/envelope_golden/):
//!   layout.cbor, timeline.cbor, action.cbor, aqueduct.cbor,
//!   element_tag.cbor, trust_observation.cbor, inscription.cbor,
//!   mythos.cbor, archiform.cbor
//!
//! Each file contains raw dCBOR bytes produced by the canonical Zig encoder.
//! The Vitest round-trip tests decode these via cbor.ts, validate with
//! Valibot, and for CLI-path envelopes (Timeline, Action, Aqueduct, Mythos)
//! assert structural equality after re-parse.

const std = @import("std");
const dreamball = @import("dreamball");
const v2 = dreamball.protocol_v2;
const protocol = dreamball.protocol;
const ev2 = dreamball.envelope_v2;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const io = std.Io.Threaded.global_single_threaded.io();

    // Ensure output directory exists.
    std.Io.Dir.cwd().createDirPath(io, "fixtures/envelope_golden") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    // ── layout ──────────────────────────────────────────────────────────────
    {
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
        const bytes = try ev2.encodeLayout(gpa, l);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/layout.cbor", bytes);
    }

    // ── timeline ─────────────────────────────────────────────────────────────
    {
        var heads = [_][32]u8{[_]u8{0xAA} ** 32};
        const t = v2.Timeline{
            .palace_fp = [_]u8{0} ** 32,
            .head_hashes = &heads,
        };
        const bytes = try ev2.encodeTimeline(gpa, t);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/timeline.cbor", bytes);
    }

    // ── action ───────────────────────────────────────────────────────────────
    {
        var parents = [_][32]u8{[_]u8{0x10} ** 32};
        const a = v2.Action{
            .action_kind = .palace_minted,
            .actor = [_]u8{0x01} ** 32,
            .parent_hashes = &parents,
        };
        const bytes = try ev2.encodeAction(gpa, a);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/action.cbor", bytes);
    }

    // ── aqueduct ─────────────────────────────────────────────────────────────
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
        try writeFixture(io, "fixtures/envelope_golden/aqueduct.cbor", bytes);
    }

    // ── element-tag ──────────────────────────────────────────────────────────
    {
        const et = v2.ElementTag{
            .element = "fire",
            .phase = "yang",
        };
        const bytes = try ev2.encodeElementTag(gpa, et);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/element_tag.cbor", bytes);
    }

    // ── trust-observation ────────────────────────────────────────────────────
    {
        const axes = [_]v2.TrustAxis{
            .{ .name = "reliability", .value = 0.8, .range = .{ 0.0, 1.0 } },
            .{ .name = "alignment", .value = 0.6, .range = .{ 0.0, 1.0 } },
        };
        const sig_val = [_]u8{0xAA} ** 64;
        const sigs = [_]protocol.Signature{
            .{ .alg = "ed25519", .value = &sig_val },
        };
        const to = v2.TrustObservation{
            .observer = [_]u8{0x01} ** 32,
            .about = [_]u8{0x02} ** 32,
            .axes = &axes,
            .signatures = &sigs,
        };
        const bytes = try ev2.encodeTrustObservation(gpa, to);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/trust_observation.cbor", bytes);
    }

    // ── inscription ──────────────────────────────────────────────────────────
    {
        const ins = v2.Inscription{
            .surface = "scroll",
            .placement = "curator",
            .note = "# Hello\n\nA short markdown inscription.",
        };
        const bytes = try ev2.encodeInscription(gpa, ins);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/inscription.cbor", bytes);
    }

    // ── mythos ───────────────────────────────────────────────────────────────
    {
        const m = v2.Mythos{
            .is_genesis = true,
            .discovered_in = [_]u8{0xCC} ** 32,
            .true_name = "The Palace of Remembered Light",
            .authored_at = 1_700_000_000,
        };
        const bytes = try ev2.encodeMythos(gpa, m);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/mythos.cbor", bytes);
    }

    // ── archiform ────────────────────────────────────────────────────────────
    {
        const ar = v2.Archiform{
            .form = "library",
            .tradition = "hermetic",
            .parent_form = "forge",
        };
        const bytes = try ev2.encodeArchiform(gpa, ar);
        defer gpa.free(bytes);
        try writeFixture(io, "fixtures/envelope_golden/archiform.cbor", bytes);
    }

    const stdout = std.Io.File.stdout();
    var buf: [512]u8 = undefined;
    var w = stdout.writer(io, &buf);
    try w.interface.print(
        "export-envelope-fixtures: wrote 9 files to fixtures/envelope_golden/\n",
        .{},
    );
    try w.interface.flush();
}

fn writeFixture(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var w = file.writer(io, &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}
