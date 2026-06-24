//! `dreamball export-json <in> --out <out>` — write canonical JSON rendering.
//!
//! Uses the full `decodeDreamBall` so every mutable attribute (name,
//! look/feel/act, guilds, contains, derived-from, signatures, …) survives
//! into the JSON output, not just the tag-201 subject's core fields.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "out" },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(1) or parsed.positional.items.len == 0) {
        try io.writeAllStdout("dreamball export-json <in.ball> --out <out.ball.json>\n");
        return 0;
    }

    const in_path = parsed.positional.items[0];
    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };

    const bytes = try helpers.readFile(gpa, in_path);
    defer gpa.free(bytes);

    // The full decoder allocates strings and nested slices into the arena;
    // writeDreamBall consumes them before we return.
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const db = try dreamball.envelope.decodeDreamBall(arena.allocator(), bytes);

    const jtext = try dreamball.json.writeDreamBall(gpa, db);
    defer gpa.free(jtext);

    try helpers.writeFile(out_path, jtext);
    try io.printStdout("exported → {s} ({d} bytes)\n", .{ out_path, jtext.len });
    return 0;
}
