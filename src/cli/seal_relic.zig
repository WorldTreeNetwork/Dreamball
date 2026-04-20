//! `jelly seal-relic <inner.jelly> --for-guild=<guild-fp-b58> --out=<relic.jelly> [--hint=<text>]`
//!
//! Produces a `jelly.dreamball.relic` that wraps the inner DreamBall. The
//! actual encryption is MOCKED (A2): the inner bytes are stored verbatim as
//! the sealed payload, and the sealed-payload-hash is the Blake3 of those
//! bytes. TODO-CRYPTO: replace with real recrypt proxy-recryption before prod.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "for-guild" },
    .{ .long = "out" },
    .{ .long = "hint" },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(3) or parsed.positional.items.len == 0) {
        try io.writeAllStdout(
            \\jelly seal-relic <inner.jelly> --for-guild <guild-fp-b58> --out <relic.jelly> [--hint <text>]
            \\
        );
        return 0;
    }

    const inner_path = parsed.positional.items[0];
    const guild_b58 = parsed.get(0) orelse {
        try io.writeAllStderr("error: --for-guild is required\n");
        return 2;
    };
    const out_path = parsed.get(1) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };
    const hint = parsed.get(2);

    const inner_bytes = try helpers.readFile(gpa, inner_path);
    defer gpa.free(inner_bytes);
    const guild_fp_bytes = try dreamball.base58.decode(gpa, guild_b58);
    defer gpa.free(guild_fp_bytes);
    if (guild_fp_bytes.len != 32) {
        try io.writeAllStderr("error: --for-guild must decode to 32 bytes\n");
        return 2;
    }
    var unlock_guild: dreamball.Fingerprint = undefined;
    @memcpy(&unlock_guild.bytes, guild_fp_bytes);

    // Compute Blake3 of the inner bytes — this is the sealed-payload-hash.
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(inner_bytes);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    // Generate a fresh Ed25519 identity for the Relic wrapper itself.
    // The wrapper is ephemeral — its identity has no persisted key file and
    // therefore no durable ML-DSA pubkey to publish. Accept Ed25519-only here
    // per the "lower-stakes context" policy; the inner DreamBall carries its
    // own hybrid signatures independently.
    const relic_keys = try dreamball.SigningKeys.generate();
    const relic_identity = relic_keys.ed25519_public;
    var genesis_input: [64]u8 = undefined;
    @memcpy(genesis_input[0..32], &relic_identity);
    @memcpy(genesis_input[32..64], &hash);
    var gh: [32]u8 = undefined;
    var gh_hasher = std.crypto.hash.Blake3.init(.{});
    gh_hasher.update(&genesis_input);
    gh_hasher.final(&gh);

    const relic: dreamball.protocol_v2.Relic = .{
        .sealed_payload_hash = hash,
        .unlock_guild = unlock_guild,
    };

    // Encode the relic envelope.
    const unsigned = try dreamball.envelope_v2.encodeRelic(gpa, relic_identity, gh, relic, hint, &.{});
    defer gpa.free(unsigned);

    // Sign with the relic's own keypair (Ed25519 only — see note above).
    const sig_bytes = try dreamball.signer.signEd25519(unsigned, relic_keys);
    const sigs = [_]dreamball.protocol.Signature{
        .{ .alg = "ed25519", .value = &sig_bytes },
    };
    const signed_envelope = try dreamball.envelope_v2.encodeRelic(gpa, relic_identity, gh, relic, hint, &sigs);
    defer gpa.free(signed_envelope);

    // Wrap in a DragonBall sealed-file with the inner bytes as attachment 0.
    const Attachment = dreamball.sealing.Attachment;
    const attachments = [_]Attachment{.{ .bytes = inner_bytes }};
    const sealed_file = try dreamball.sealing.writeSealedFile(
        gpa,
        signed_envelope,
        .{ .encrypted = true }, // TODO-CRYPTO: bit set to match spec even though bytes aren't actually encrypted
        .plain,
        &attachments,
    );
    defer gpa.free(sealed_file);

    try helpers.writeFile(out_path, sealed_file);
    try io.printStdout("sealed relic → {s} ({d} bytes)\n", .{ out_path, sealed_file.len });
    try io.writeAllStderr("warning: relic encryption is MOCKED; inner bytes are stored plaintext (TODO-CRYPTO)\n");
    return 0;
}
