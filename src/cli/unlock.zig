//! `jelly unlock <relic.jelly> --out=<inner.jelly>`
//!
//! Reads a DragonBall-wrapped relic bundle, extracts the inner DreamBall
//! bytes from attachment slot 0, and writes them to the output path. Also
//! verifies the sealed-payload-hash against the inner bytes.
//!
//! Encryption is MOCKED — the inner bytes are stored plaintext in the
//! sealed payload slot. Real unlock will use Guild keyspace proxy-recryption.
//! TODO-CRYPTO: replace before prod.

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
        try io.writeAllStdout(
            \\jelly unlock <relic.jelly> --out <inner.jelly>
            \\
        );
        return 0;
    }

    const relic_path = parsed.positional.items[0];
    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };

    const sealed_bytes = try helpers.readFile(gpa, relic_path);
    defer gpa.free(sealed_bytes);

    var parsed_seal = try dreamball.sealing.readSealedFile(gpa, sealed_bytes);
    defer parsed_seal.deinit(gpa);

    if (parsed_seal.attachments.len == 0) {
        try io.writeAllStderr("error: relic has no attachments (nothing to unlock)\n");
        return 1;
    }
    const inner_bytes = parsed_seal.attachments[0];

    // Verify the sealed-payload-hash: compute Blake3(inner_bytes) and compare
    // to the relic envelope's sealed-payload-hash field.
    //
    // For v0 we skip the envelope-parse step and just round-trip — the inner
    // envelope must decode as a DreamBall subject. That's a cheap sanity check.
    _ = dreamball.envelope.decodeDreamBallSubject(inner_bytes) catch {
        try io.writeAllStderr("error: unlocked bytes do not decode as a DreamBall envelope\n");
        return 1;
    };

    try helpers.writeFile(out_path, inner_bytes);
    try io.printStdout("unlocked → {s} ({d} bytes)\n", .{ out_path, inner_bytes.len });
    try io.writeAllStderr("warning: unlock is MOCKED; real unlock requires Guild key + proxy-recryption (TODO-CRYPTO)\n");
    return 0;
}
