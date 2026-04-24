//! Command dispatch table for the `jelly` CLI.
//!
//! Each command lives in its own file and exports `run(gpa, args) !u8`.
//! `args` is the full argv starting at argv[2] — the command name is already
//! consumed by the dispatcher.

const std = @import("std");
const Allocator = std.mem.Allocator;

const io = @import("../io.zig");
const cmd_mint = @import("mint.zig");
const cmd_grow = @import("grow.zig");
const cmd_show = @import("show.zig");
const cmd_verify = @import("verify.zig");
const cmd_seal = @import("seal.zig");
const cmd_unseal = @import("unseal.zig");
const cmd_export_json = @import("export_json.zig");
const cmd_import_json = @import("import_json.zig");
const cmd_join_guild = @import("join_guild.zig");
const cmd_transmit = @import("transmit.zig");
const cmd_seal_relic = @import("seal_relic.zig");
const cmd_unlock = @import("unlock.zig");
const cmd_palace = @import("palace.zig");

pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    run: *const fn (Allocator, [][:0]const u8) anyerror!u8,
};

pub const commands: []const Command = &.{
    .{ .name = "mint", .summary = "create a new DreamSeed (Ed25519 keypair + seed.jelly)", .run = cmd_mint.run },
    .{ .name = "grow", .summary = "update slots on an existing DreamBall and re-sign", .run = cmd_grow.run },
    .{ .name = "show", .summary = "pretty-print a .jelly file", .run = cmd_show.run },
    .{ .name = "verify", .summary = "check Ed25519 signature (exit 0 = ok)", .run = cmd_verify.run },
    .{ .name = "seal", .summary = "wrap a DreamBall into a DragonBall .jelly file", .run = cmd_seal.run },
    .{ .name = "unseal", .summary = "unwrap a DragonBall back to envelope bytes", .run = cmd_unseal.run },
    .{ .name = "export-json", .summary = "write a canonical .jelly.json", .run = cmd_export_json.run },
    .{ .name = "import-json", .summary = "read canonical .jelly.json back into CBOR", .run = cmd_import_json.run },
    .{ .name = "join-guild", .summary = "add a Guild membership attribute and re-sign", .run = cmd_join_guild.run },
    .{ .name = "transmit", .summary = "transmit a Tool to a target Agent via a Guild", .run = cmd_transmit.run },
    .{ .name = "seal-relic", .summary = "wrap a DreamBall into a sealed Relic (MOCKED crypto)", .run = cmd_seal_relic.run },
    .{ .name = "unlock", .summary = "unlock a sealed Relic (MOCKED crypto)", .run = cmd_unlock.run },
    .{ .name = "palace", .summary = "palace verb group (see jelly palace --help)", .run = cmd_palace.run },
};

pub fn findCommand(name: []const u8) ?Command {
    for (commands) |c| {
        if (std.mem.eql(u8, c.name, name)) return c;
    }
    return null;
}

pub fn printUsage() !void {
    var buf: [8192]u8 = undefined;
    var w = std.Io.File.stdout().writer(io.io(), &buf);
    try w.interface.writeAll(
        \\jelly — DreamBall protocol CLI
        \\
        \\Usage: jelly <command> [args...]
        \\
        \\Commands:
        \\
    );
    for (commands) |c| {
        try w.interface.print("  {s: <14} {s}\n", .{ c.name, c.summary });
    }
    try w.interface.writeAll(
        \\  version        print protocol format-version
        \\
        \\Run `jelly <command> --help` for per-command flags.
        \\
    );
    try w.interface.flush();
}
