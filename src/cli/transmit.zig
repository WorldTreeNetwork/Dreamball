//! `jelly transmit <tool.jelly> --to=<target-fp-b58> --via-guild=<guild-fp-b58> --sender-key=<keyfile> --out=<transmission.jelly>`
//!
//! Produces a signed `jelly.transmission` receipt recording the transfer of
//! a Tool DreamBall to a target Agent via a shared Guild. Crypto is mocked
//! per A2 (Ed25519 signing is real; no proxy-recryption).

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "to" },
    .{ .long = "via-guild" },
    .{ .long = "sender-key" },
    .{ .long = "out" },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(4) or parsed.positional.items.len == 0) {
        try io.writeAllStdout(
            \\jelly transmit <tool.jelly> --to <target-fp-b58> --via-guild <guild-fp-b58> --sender-key <keyfile> --out <receipt.jelly>
            \\
        );
        return 0;
    }

    const tool_path = parsed.positional.items[0];
    const target_b58 = parsed.get(0) orelse return missing("--to");
    const guild_b58 = parsed.get(1) orelse return missing("--via-guild");
    const sender_key = parsed.get(2) orelse return missing("--sender-key");
    const out_path = parsed.get(3) orelse return missing("--out");

    const tool_bytes = try helpers.readFile(gpa, tool_path);
    defer gpa.free(tool_bytes);
    const tool_db = try dreamball.envelope.decodeDreamBallSubject(tool_bytes);

    const target_fp_bytes = try dreamball.base58.decode(gpa, target_b58);
    defer gpa.free(target_fp_bytes);
    const guild_fp_bytes = try dreamball.base58.decode(gpa, guild_b58);
    defer gpa.free(guild_fp_bytes);
    if (target_fp_bytes.len != 32 or guild_fp_bytes.len != 32) {
        try io.writeAllStderr("error: fingerprints must decode to 32 bytes\n");
        return 2;
    }

    const key_bytes = try helpers.readFile(gpa, sender_key);
    defer gpa.free(key_bytes);
    if (key_bytes.len != 64) {
        try io.writeAllStderr("error: sender key must be 64 bytes\n");
        return 2;
    }
    var sk_bytes: [64]u8 = undefined;
    @memcpy(&sk_bytes, key_bytes);
    const sk = try std.crypto.sign.Ed25519.SecretKey.fromBytes(sk_bytes);
    const kp = try std.crypto.sign.Ed25519.KeyPair.fromSecretKey(sk);

    const tool_fp = tool_db.fingerprint();
    var target_fp: dreamball.Fingerprint = undefined;
    @memcpy(&target_fp.bytes, target_fp_bytes);
    var via_guild: dreamball.Fingerprint = undefined;
    @memcpy(&via_guild.bytes, guild_fp_bytes);
    const sender_fp = dreamball.Fingerprint.fromEd25519(kp.public_key.toBytes());

    var t = dreamball.protocol_v2.Transmission{
        .tool_fp = tool_fp,
        .target_fp = target_fp,
        .via_guild = via_guild,
        .sender_fp = sender_fp,
        .transmitted_at = io.unixSeconds(),
        .tool_envelope = tool_bytes,
    };

    // Sign the unsigned transmission bytes.
    const unsigned = try dreamball.envelope_v2.encodeTransmission(gpa, t);
    defer gpa.free(unsigned);
    const sig = try kp.sign(unsigned, null);
    const sig_bytes = sig.toBytes();
    const mldsa_ph = try dreamball.signer.mlDsaPlaceholder(gpa);
    defer gpa.free(mldsa_ph);
    const sigs = [_]dreamball.protocol.Signature{
        .{ .alg = "ed25519", .value = &sig_bytes },
        .{ .alg = "ml-dsa-87", .value = mldsa_ph },
    };
    t.signatures = &sigs;

    const signed = try dreamball.envelope_v2.encodeTransmission(gpa, t);
    defer gpa.free(signed);
    try helpers.writeFile(out_path, signed);

    try io.printStdout(
        "transmitted {s} → {s} via guild {s}\nreceipt: {s} ({d} bytes)\n",
        .{ tool_path, target_b58, guild_b58, out_path, signed.len },
    );
    // TODO-CRYPTO: replace before prod — real transmission requires recrypt
    // proxy-recryption so the receiver can decrypt the Tool's secrets.
    try io.writeAllStderr("warning: transmission crypto is mocked (Ed25519 sig real; proxy-recryption stub)\n");
    return 0;
}

fn missing(flag: []const u8) !u8 {
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "error: {s} is required\n", .{flag}) catch "error: missing required flag\n";
    try io.writeAllStderr(msg);
    return 2;
}
