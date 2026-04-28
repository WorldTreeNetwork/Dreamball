//! Palace verb group dispatch (D-013).
//!
//! Routes `jelly palace <subverb>` to per-subverb handlers that live in
//! separate files. Each subverb handler exports `run(gpa, args) !u8` with
//! the same signature as top-level commands.

const std = @import("std");
const Allocator = std.mem.Allocator;

const io = @import("../io.zig");
// Story 3.2 — `mint` is dispatched through the generated CLI projection
// at src/cli/generated/palace_mint.zig (D-019/D-022/D-024).
// Story 3.3 — `inscribe` and `add-room` are also projected via generated
// dispatchers at src/cli/generated/palace_inscribe.zig and
// src/cli/generated/palace_add_room.zig.
// The legacy hand-written verbs remain in place for parity verification;
// each generated dispatcher delegates to its legacy `run` after flag
// parsing + help + confirmation. Story 3.5 removes the legacy files
// once all five verbs project cleanly.
const palace_mint = @import("generated/palace_mint.zig");
const palace_add_room = @import("generated/palace_add_room.zig");
const palace_inscribe = @import("generated/palace_inscribe.zig");
const palace_move = @import("palace_move.zig");
const palace_open = @import("palace_open.zig");
const palace_rename_mythos = @import("palace_rename_mythos.zig");
const palace_show = @import("palace_show.zig");

pub const SubCommand = struct {
    name: []const u8,
    summary: []const u8,
    run: *const fn (Allocator, [][:0]const u8) anyerror!u8,
};

pub const subcommands: []const SubCommand = &.{
    .{ .name = "mint", .summary = "mint a new palace DreamBall with required mythos", .run = palace_mint.run },
    .{ .name = "add-room", .summary = "add a room to an existing palace", .run = palace_add_room.run },
    .{ .name = "inscribe", .summary = "inscribe an avatar into a palace room", .run = palace_inscribe.run },
    .{ .name = "move", .summary = "move an inscription from one room to another", .run = palace_move.run },
    .{ .name = "open", .summary = "open a palace at a deep-linked room/inscription", .run = palace_open.run },
    .{ .name = "rename-mythos", .summary = "append a new canonical mythos head (true-naming)", .run = palace_rename_mythos.run },
    .{ .name = "show", .summary = "show palace topology or list archiforms (AC4)", .run = palace_show.run },
};

pub fn printPalaceUsage() !void {
    try io.writeAllStdout(
        \\Usage: jelly palace <subverb> [args...]
        \\
        \\Subverbs:
        \\  mint            mint a new palace DreamBall with required mythos
        \\  add-room        add a room to an existing palace
        \\  inscribe        inscribe an avatar into a palace room
        \\  move            move an inscription from one room to another
        \\  open            open a palace at a deep-linked room/inscription
        \\  rename-mythos   append a new canonical mythos head (true-naming)
        \\  show            show palace topology or list archiforms
        \\
        \\Growth (unimplemented):
        \\  layout, share, rewind, observe
        \\
        \\Run `jelly palace <subverb> --help` for per-subverb flags.
        \\
    );
}

pub fn run(gpa: Allocator, args: [][:0]const u8) !u8 {
    // No subverb: print usage, exit non-zero (AC3)
    if (args.len == 0) {
        try printPalaceUsage();
        return 2;
    }

    // --help / -h: print usage, exit 0 (AC2)
    if (std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        try printPalaceUsage();
        return 0;
    }

    // Find matching subcommand
    for (subcommands) |sub| {
        if (std.mem.eql(u8, args[0], sub.name)) {
            return sub.run(gpa, args[1..]);
        }
    }

    // Unknown subverb: print usage, exit non-zero (AC5)
    try printPalaceUsage();
    return 2;
}
