//! `jelly` CLI entry.

const std = @import("std");
const dreamball = @import("dreamball");
const io = @import("io.zig");
const dispatch = @import("cli/dispatch.zig");

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args_iter.deinit();

    var argv_list: std.ArrayList([:0]const u8) = .empty;
    defer argv_list.deinit(gpa);
    while (args_iter.next()) |a| {
        try argv_list.append(gpa, a);
    }
    if (argv_list.items.len < 2) {
        try dispatch.printUsage();
        return 0;
    }

    const cmd_name = argv_list.items[1];

    if (std.mem.eql(u8, cmd_name, "version")) {
        try io.printStdout("dreamball protocol format-version {d}\n", .{dreamball.protocol.FORMAT_VERSION});
        return 0;
    }
    if (std.mem.eql(u8, cmd_name, "--help") or std.mem.eql(u8, cmd_name, "help")) {
        try dispatch.printUsage();
        return 0;
    }

    const cmd = dispatch.findCommand(cmd_name) orelse {
        try io.printStdout("unknown command: {s}\n", .{cmd_name});
        try dispatch.printUsage();
        return 1;
    };

    return try cmd.run(gpa, argv_list.items[2..]);
}
