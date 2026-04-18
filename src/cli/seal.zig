//! `jelly seal <in> --out <out> [--compress]` — wrap a DreamBall in a
//! DragonBall file header. zstd compression is opt-in when --compress is
//! passed; otherwise the envelope bytes are stored verbatim.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "out" },
    .{ .long = "compress", .takes_value = false },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(2) or parsed.positional.items.len == 0) {
        try io.writeAllStdout(
            \\jelly seal <in.jelly> --out <out.dragon.jelly> [--compress]
            \\
        );
        return 0;
    }

    const in_path = parsed.positional.items[0];
    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };
    const compress = parsed.flag(1);

    const envelope_bytes = try helpers.readFile(gpa, in_path);
    defer gpa.free(envelope_bytes);

    if (compress) {
        // Zig 0.16 std.compress.zstd ships a Decompress but no Compress. Until a
        // pure-Zig zstd compressor lands upstream (or we vendor one), refuse
        // rather than silently produce an uncompressed file with the compressed
        // flag set — that would corrupt the DragonBall semantic.
        try io.writeAllStderr("error: --compress is not yet implemented (std.compress.zstd lacks a compressor on Zig 0.16)\n");
        return 2;
    }

    const sealed = try dreamball.sealing.writeSealedFile(
        gpa,
        envelope_bytes,
        .{},
        .plain,
        &.{},
    );
    defer gpa.free(sealed);

    try helpers.writeFile(out_path, sealed);
    try io.printStdout("sealed → {s} ({d} bytes)\n", .{ out_path, sealed.len });
    return 0;
}
