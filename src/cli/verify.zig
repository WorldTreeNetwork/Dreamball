//! `jelly verify <file>` — check Ed25519 signature over the canonical
//! unsigned bytes. ML-DSA-87 real verification is pending the liboqs binding;
//! the placeholder slot is accepted with a warning.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(0) or parsed.positional.items.len == 0) {
        try io.writeAllStdout("jelly verify <file.jelly>\n");
        return 0;
    }

    const path = parsed.positional.items[0];
    const bytes = helpers.readFile(gpa, path) catch {
        try io.writeAllStderr("error: could not read file\n");
        return 2;
    };
    defer gpa.free(bytes);

    const db = dreamball.envelope.decodeDreamBallSubject(bytes) catch {
        try io.writeAllStderr("error: envelope failed to parse\n");
        return 1;
    };

    var stripped = dreamball.envelope.stripSignatures(gpa, bytes) catch {
        try io.writeAllStderr("error: could not strip signatures\n");
        return 1;
    };
    defer stripped.deinit();

    var have_valid_ed = false;
    var have_mldsa_placeholder = false;

    for (stripped.signatures) |sig| {
        if (std.mem.eql(u8, sig.alg, "ed25519")) {
            if (sig.value.len != dreamball.protocol.ED25519_SIGNATURE_LEN) {
                try io.writeAllStderr("error: malformed Ed25519 signature length\n");
                return 1;
            }
            var sig_arr: [64]u8 = undefined;
            @memcpy(&sig_arr, sig.value);
            const ed_sig = std.crypto.sign.Ed25519.Signature.fromBytes(sig_arr);
            const pk = std.crypto.sign.Ed25519.PublicKey.fromBytes(db.identity) catch {
                try io.writeAllStderr("error: envelope identity is not a valid Ed25519 public key\n");
                return 1;
            };
            ed_sig.verify(stripped.unsigned, pk) catch {
                try io.writeAllStderr("error: Ed25519 signature verification failed\n");
                return 1;
            };
            have_valid_ed = true;
        } else if (std.mem.eql(u8, sig.alg, "ml-dsa-87")) {
            if (dreamball.signer.isPlaceholderMldsa(sig.value)) {
                have_mldsa_placeholder = true;
            } else {
                // Real ML-DSA verification needs a liboqs binding — not yet wired.
                try io.writeAllStderr("warning: non-placeholder ML-DSA-87 signature present but real verification is not yet implemented\n");
            }
        }
    }

    if (!have_valid_ed) {
        try io.writeAllStderr("error: no valid Ed25519 signature found\n");
        return 1;
    }
    if (have_mldsa_placeholder) {
        try io.writeAllStderr("warning: ML-DSA-87 signature is a zero-filled placeholder (liboqs binding pending)\n");
    }

    return 0;
}
