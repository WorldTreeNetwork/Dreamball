//! `jelly show <file> [--format=text|json]` — pretty-print a DreamBall or
//! identity envelope.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");
const identity_envelope = dreamball.identity_envelope;
const base58 = dreamball.base58;
const cbor = dreamball.cbor;

const SPECS = [_]args_mod.Spec{
    .{ .long = "format" },
    .{ .long = "help", .takes_value = false },
};

/// Render an identity envelope summary to a `*std.Io.Writer`.
fn renderIdentity(gpa: Allocator, identity: identity_envelope.Identity, w: *std.Io.Writer) !void {
    const fp_b58 = try base58.encode(gpa, &identity.fingerprint);
    defer gpa.free(fp_b58);

    try w.print("Identity\n", .{});
    try w.print("  fingerprint:  {s}\n", .{fp_b58});

    // name
    if (identity.name) |n| {
        try w.print("  name:         {s}\n", .{n});
    } else {
        try w.print("  name:         (unset)\n", .{});
    }

    // created — RFC 3339 YYYY-MM-DDTHH:MM:SSZ
    if (identity.created) |ts| {
        const secs_per_min: u64 = 60;
        const secs_per_hour: u64 = 3600;
        const secs_per_day: u64 = 86400;

        const days = ts / secs_per_day;
        const secs_in_day = ts % secs_per_day;
        const hh = secs_in_day / secs_per_hour;
        const mm = (secs_in_day % secs_per_hour) / secs_per_min;
        const ss = secs_in_day % secs_per_min;

        // Julian Day Number calculation for Gregorian calendar
        const jd = days + 2440588;
        const a = jd + 32044;
        const b = (4 * a + 3) / 146097;
        const c = a - (146097 * b) / 4;
        const d = (4 * c + 3) / 1461;
        const e = c - (1461 * d) / 4;
        const mo = (5 * e + 2) / 153;
        const day = e - (153 * mo + 2) / 5 + 1;
        const month = mo + 3 - 12 * (mo / 10);
        const year = 100 * b + d - 4800 + mo / 10;

        try w.print("  created:      {d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z\n", .{
            year, month, day, hh, mm, ss,
        });
    } else {
        try w.print("  created:      (unset)\n", .{});
    }

    // ed25519: public is always present in a decoded identity
    const ed_sec = if (identity.ed25519_secret != null) "secret \u{2713}" else "secret \u{2014}";
    try w.print("  ed25519:      public \u{2713}  {s}\n", .{ed_sec});

    // ml-dsa-87
    if (identity.ml_dsa) |ml| {
        const ml_sec = if (ml.secret != null) "secret \u{2713}" else "secret \u{2014}";
        try w.print("  ml-dsa-87:    public \u{2713}  {s}\n", .{ml_sec});
    } else {
        try w.print("  ml-dsa-87:    \u{2014}  \u{2014}\n", .{});
    }

    // pre
    if (identity.pre) |pre| {
        const pre_sec = if (pre.secret != null) "secret \u{2713}" else "secret \u{2014}";
        try w.print("  pre:          {s}: public \u{2713}  {s}\n", .{ pre.backend, pre_sec });
    } else {
        try w.print("  pre:          (none)\n", .{});
    }

    // unknown-asserts
    const ua_len = identity.unknown_assertions.len;
    if (ua_len == 0) {
        try w.print("  unknown-asserts: 0\n", .{});
    } else {
        try w.print("  unknown-asserts: {d}: ", .{ua_len});
        const limit = @min(ua_len, 5);
        var i: usize = 0;
        while (i < limit) : (i += 1) {
            if (i > 0) try w.print(", ", .{});
            const ua = identity.unknown_assertions[i];
            var r = cbor.Reader.init(ua.predicate_cbor);
            const pred_str = r.readText() catch "<non-text>";
            try w.print("{s}", .{pred_str});
        }
        if (ua_len > 5) try w.print(", \u{2026}", .{});
        try w.print("\n", .{});
    }
}

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(1) or parsed.positional.items.len == 0) {
        try io.writeAllStdout(
            \\jelly show <file.jelly> [--format=text|json]
            \\
        );
        return 0;
    }

    const path = parsed.positional.items[0];
    const format: []const u8 = parsed.get(0) orelse "text";

    const bytes = try helpers.readFile(gpa, path);
    defer gpa.free(bytes);

    // Detect identity envelope: CBOR tag 200 = 0xd8 0xc8
    if (bytes.len >= 2 and bytes[0] == 0xd8 and bytes[1] == 0xc8) {
        var identity = identity_envelope.decode(gpa, bytes) catch |err| switch (err) {
            error.WrongEnvelopeType => {
                // Not a recrypt.identity — fall through to DreamBall path
                return showDreamBall(gpa, path, bytes, format);
            },
            else => return err,
        };
        defer identity.deinit(gpa);

        var buf: [16384]u8 = undefined;
        var w = std.Io.File.stdout().writer(io.io(), &buf);
        try renderIdentity(gpa, identity, &w.interface);
        try w.interface.flush();
        return 0;
    }

    return showDreamBall(gpa, path, bytes, format);
}

fn showDreamBall(gpa: Allocator, path: []const u8, bytes: []const u8, format: []const u8) !u8 {
    const db = try dreamball.envelope.decodeDreamBallSubject(bytes);

    if (std.mem.eql(u8, format, "json")) {
        const json = try dreamball.json.writeDreamBall(gpa, db);
        defer gpa.free(json);
        try io.writeAllStdout(json);
        try io.writeAllStdout("\n");
        return 0;
    }

    const fp = db.fingerprint();
    const fp_b58 = try dreamball.base58.encode(gpa, &fp.bytes);
    defer gpa.free(fp_b58);
    const type_label = if (db.dreamball_type) |t| t.tag() else "untyped";
    try io.printStdout(
        "DreamBall {s}\n  type:         {s}\n  stage:        {s}\n  fingerprint:  {s}\n  revision:     {d}\n  bytes:        {d}\n",
        .{ path, type_label, db.stage.toString(), fp_b58, db.revision, bytes.len },
    );
    return 0;
}

// ============================================================================
// Tests
// ============================================================================

test "show renders identity envelope summary for hybrid fixture" {
    const allocator = std.testing.allocator;

    const fixture = @embedFile("../recrypt-identity-fixtures/identity-hybrid-no-pre.envelope");

    var identity = try identity_envelope.decode(allocator, fixture);
    defer identity.deinit(allocator);

    // Build expected fingerprint base58 from JSON sidecar
    const expected_fp_hex = "34a374a71ce45a64cef46deae14583ab4a1754f8e3539b44f346c813844851c3";
    var expected_fp: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_fp, expected_fp_hex);
    const expected_fp_b58 = try base58.encode(allocator, &expected_fp);
    defer allocator.free(expected_fp_b58);

    // Render into a fixed buffer using std.Io.Writer.fixed
    var out_buf: [65536]u8 = undefined;
    var w = std.Io.Writer.fixed(&out_buf);
    try renderIdentity(allocator, identity, &w);
    try w.flush();

    const output = out_buf[0..w.end];

    // Assert key substrings are present
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "Identity"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "fingerprint:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, expected_fp_b58));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "ed25519:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "public \u{2713}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "secret \u{2713}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "ml-dsa-87:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "pre:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "(none)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "unknown-asserts: 1: dreamball-lineage"));
}
