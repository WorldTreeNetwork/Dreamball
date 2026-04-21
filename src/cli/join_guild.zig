//! `jelly join-guild <dreamball.jelly> --guild=<guild.jelly> --key=<keyfile>`
//! Appends a `guild` attribute (the Guild's fingerprint) to the DreamBall,
//! bumps revision, and re-signs with the provided Ed25519 secret.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "guild" },
    .{ .long = "key" },
    .{ .long = "out" },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(3) or parsed.positional.items.len == 0) {
        try io.writeAllStdout(
            \\jelly join-guild <dreamball.jelly> --guild <guild.jelly> --key <keyfile> [--out <path>]
            \\
            \\Adds a Guild membership attribute to the DreamBall and re-signs.
            \\
        );
        return 0;
    }

    const db_path = parsed.positional.items[0];
    const guild_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --guild is required\n");
        return 2;
    };
    const key_path = parsed.get(1) orelse {
        try io.writeAllStderr("error: --key is required\n");
        return 2;
    };
    const out_path = parsed.get(2) orelse db_path;

    const db_bytes = try helpers.readFile(gpa, db_path);
    defer gpa.free(db_bytes);
    const guild_bytes = try helpers.readFile(gpa, guild_path);
    defer gpa.free(guild_bytes);

    var db = try dreamball.envelope.decodeDreamBallSubject(db_bytes);
    const guild_db = try dreamball.envelope.decodeDreamBallSubject(guild_bytes);

    // Append the Guild's fingerprint to the db's guilds list.
    const guild_fp = guild_db.fingerprint();
    const new_guilds = try gpa.alloc(dreamball.Fingerprint, db.guilds.len + 1);
    defer gpa.free(new_guilds);
    @memcpy(new_guilds[0..db.guilds.len], db.guilds);
    new_guilds[db.guilds.len] = guild_fp;
    db.guilds = new_guilds;
    db.revision += 1;
    db.updated = io.unixSeconds();

    const sign = @import("sign.zig");
    const signed = try sign.signEnvelope(gpa, &db, key_path);
    defer gpa.free(signed);

    try helpers.writeFile(out_path, signed);

    const guild_fp_b58 = try dreamball.base58.encode(gpa, &guild_fp.bytes);
    defer gpa.free(guild_fp_b58);
    try io.printStdout("joined guild {s} → {s}  revision={d}\n", .{ guild_fp_b58, out_path, db.revision });
    return 0;
}
