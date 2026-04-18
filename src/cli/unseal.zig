//! `jelly unseal <in> --out <out>` — extract the inner envelope from a DragonBall.

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
        try io.writeAllStdout("jelly unseal <in.dragon.jelly> --out <out.jelly>\n");
        return 0;
    }

    const in_path = parsed.positional.items[0];
    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };

    const sealed = try helpers.readFile(gpa, in_path);
    defer gpa.free(sealed);

    var parsed_seal = try dreamball.sealing.readSealedFile(gpa, sealed);
    defer parsed_seal.deinit(gpa);

    try helpers.writeFile(out_path, parsed_seal.envelope);
    try io.printStdout("unsealed → {s} ({d} bytes)\n", .{ out_path, parsed_seal.envelope.len });
    return 0;
}
