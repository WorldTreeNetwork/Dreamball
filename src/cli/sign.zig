//! CLI-side signing helper. Reads a key file, attaches Ed25519 and
//! (when a hybrid key is available) ML-DSA-87 `'signed'` attributes to a
//! node, and returns the signed bytes. Used by `grow`, `seal-relic`,
//! `transmit`, and `join-guild` so the multi-sig wiring stays in one place.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");

/// Sign an in-memory DreamBall using the key at `key_path`.
///
/// Hybrid key file → both signatures attached, `identity_pq` populated from
/// the key's ML-DSA public key so subsequent verifiers can check the PQ sig
/// against the node's own core.
/// Legacy 64-byte key file → Ed25519-only signature. The caller's
/// `identity_pq` stays as-is (usually null); no placeholder is emitted.
///
/// Returns the caller-owned signed node bytes.
pub fn signEnvelope(
    gpa: Allocator,
    db: *dreamball.DreamBall,
    key_path: []const u8,
) ![]u8 {
    const loaded = try dreamball.key_file.readFromPath(gpa, key_path);

    switch (loaded) {
        .hybrid => |keys| {
            db.identity_pq = keys.mldsa_public;
            const unsigned = try dreamball.envelope.encodeDreamBall(gpa, db.*);
            defer gpa.free(unsigned);

            const ed_sig = try dreamball.signer.signEd25519(unsigned, keys.classical());
            const mldsa_sig = try dreamball.signer.signMlDsa(gpa, unsigned, keys);
            defer gpa.free(mldsa_sig);

            const sigs = [_]dreamball.protocol.Signature{
                .{ .alg = "ed25519", .value = &ed_sig },
                .{ .alg = "ml-dsa-87", .value = mldsa_sig },
            };
            db.signatures = &sigs;
            return dreamball.envelope.encodeDreamBall(gpa, db.*);
        },
        .ed25519_only => |keys| {
            // Legacy key file: Ed25519 only. Do not fabricate a placeholder
            // PQ signature — verifiers must be able to tell real from absent.
            db.identity_pq = null;
            const unsigned = try dreamball.envelope.encodeDreamBall(gpa, db.*);
            defer gpa.free(unsigned);
            const ed_sig = try dreamball.signer.signEd25519(unsigned, keys);
            const sigs = [_]dreamball.protocol.Signature{
                .{ .alg = "ed25519", .value = &ed_sig },
            };
            db.signatures = &sigs;
            return dreamball.envelope.encodeDreamBall(gpa, db.*);
        },
    }
}
