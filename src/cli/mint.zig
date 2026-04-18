//! `jelly mint --out <path> [--name <str>]` — create a new DreamSeed with a
//! freshly generated Ed25519 identity. Writes:
//!   <out>           canonical dCBOR envelope bytes
//!   <out>.key       raw 64-byte Ed25519 secret, permissions 0600

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "out" },
    .{ .long = "name" },
    .{ .long = "type" },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(3)) {
        try io.writeAllStdout(
            \\jelly mint --out <path> [--name <string>] [--type <type>]
            \\
            \\Creates a new DreamSeed with a freshly generated Ed25519 identity.
            \\Writes <out> (CBOR envelope) and <out>.key (raw secret, 0600).
            \\
            \\--type is one of: avatar, agent, tool, relic, field, guild.
            \\  (omit --type for the v1-compatible untyped shape)
            \\
        );
        return 0;
    }

    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };
    const name = parsed.get(1);
    const type_str = parsed.get(2);
    const dreamball_type: ?dreamball.protocol.DreamBallType = if (type_str) |s|
        dreamball.protocol.DreamBallType.fromTag(s) orelse {
            try io.writeAllStderr("error: --type must be one of: avatar, agent, tool, relic, field, guild\n");
            return 2;
        }
    else
        null;

    // 1. Generate Ed25519 keypair.
    const keys = try dreamball.SigningKeys.generate();

    // 2. Build the seed DreamBall.
    const now: i64 = io.unixSeconds();
    var genesis_input: [40]u8 = undefined;
    @memcpy(genesis_input[0..32], &keys.ed25519_public);
    std.mem.writeInt(i64, genesis_input[32..40], now, .little);

    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(&genesis_input);
    var genesis_hash: [32]u8 = undefined;
    hasher.final(&genesis_hash);

    var db = dreamball.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .genesis_hash = genesis_hash,
        .revision = 0,
        .dreamball_type = dreamball_type,
        .name = name,
        .created = now,
    };

    // 3. Encode + sign (Ed25519 real, ML-DSA-87 placeholder).
    const unsigned_bytes = try dreamball.envelope.encodeDreamBall(gpa, db);
    defer gpa.free(unsigned_bytes);

    const kp = try keys.keyPair();
    const ed_sig = try kp.sign(unsigned_bytes, null);
    const ed_sig_bytes = ed_sig.toBytes();

    const mldsa_ph = try dreamball.signer.mlDsaPlaceholder(gpa);
    defer gpa.free(mldsa_ph);

    const sigs = [_]dreamball.protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig_bytes },
        .{ .alg = "ml-dsa-87", .value = mldsa_ph },
    };
    db.signatures = &sigs;

    // Re-encode with signatures attached.
    const signed_bytes = try dreamball.envelope.encodeDreamBall(gpa, db);
    defer gpa.free(signed_bytes);

    // 4. Write envelope file.
    const helpers = @import("helpers.zig");
    try helpers.writeFile(out_path, signed_bytes);

    // 5. Write key file (permissions left at default — see security note).
    const key_path = try std.fmt.allocPrint(gpa, "{s}.key", .{out_path});
    defer gpa.free(key_path);
    try helpers.writeFile(key_path, &keys.ed25519_secret);

    // 6. Report.
    const fp = db.fingerprint();
    const fp_b58 = try dreamball.base58.encode(gpa, &fp.bytes);
    defer gpa.free(fp_b58);
    const type_label = if (dreamball_type) |t| t.tag() else "untyped";
    try io.printStdout(
        "minted seed → {s}\n  type:        {s}\n  identity fingerprint: {s}\n  secret key:  {s}\n",
        .{ out_path, type_label, fp_b58, key_path },
    );
    try io.writeAllStderr("warning: ML-DSA-87 signature is a placeholder (liboqs binding pending)\n");

    return 0;
}

