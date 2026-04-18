//! `jelly import-json <in.jelly.json> --out <out.jelly>` — read canonical JSON
//! and emit canonical dCBOR. Round-trips byte-identically with files that were
//! produced by `export-json`.

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
        try io.writeAllStdout("jelly import-json <in.jelly.json> --out <out.jelly>\n");
        return 0;
    }

    const in_path = parsed.positional.items[0];
    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };

    const json_text = try helpers.readFile(gpa, in_path);
    defer gpa.free(json_text);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const db = dreamball.json.readDreamBall(arena.allocator(), json_text) catch |err| {
        try io.printStdout("error: JSON parse failed: {t}\n", .{err});
        return 1;
    };

    const cbor_bytes = try dreamball.envelope.encodeDreamBall(gpa, db);
    defer gpa.free(cbor_bytes);

    try helpers.writeFile(out_path, cbor_bytes);
    try io.printStdout("imported → {s} ({d} bytes)\n", .{ out_path, cbor_bytes.len });
    return 0;
}
