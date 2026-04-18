//! `jelly show <file> [--format=text|json]` — pretty-print a DreamBall.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "format" },
    .{ .long = "help", .takes_value = false },
};

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
    const db = try dreamball.envelope.decodeDreamBallSubject(bytes);

    if (std.mem.eql(u8, format, "json")) {
        const json = try dreamball.json.writeDreamBall(gpa, db);
        defer gpa.free(json);
        try io.writeAllStdout(json);
        try io.writeAllStdout("\n");
        return 0;
    }

    // text view
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
