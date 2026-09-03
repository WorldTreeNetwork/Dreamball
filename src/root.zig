//! DreamBall — a signed, evolvable NFT-like container for look/feel/act.
//! See docs/PROTOCOL.md for the wire format.

const std = @import("std");

pub const protocol = @import("protocol.zig");
pub const protocol_v2 = @import("protocol_v2.zig");
pub const fingerprint = @import("fingerprint.zig");
pub const base58 = @import("base58.zig");
pub const dcbor = @import("dcbor.zig");
pub const envelope = @import("envelope.zig");
pub const envelope_v2 = @import("envelope_v2.zig");
pub const sealing = @import("sealing.zig");
pub const json = @import("json.zig");
pub const signer = @import("signer.zig");
pub const graph = @import("graph.zig");
pub const ml_dsa = @import("ml_dsa.zig");
pub const key_file = @import("key_file.zig");
pub const identity_envelope = @import("identity_envelope.zig");
// DEFERRED to Dreamball-etk.1 (Dreamball-h7s.1 deletion pass, part 2): this
// re-export is the backwards dependency arrow palace code puts on the library
// root, but src/cli/internal/verify.zig:50 (`dreamball.mythos_chain`) is a
// live, in-scope-CLI consumer. It leaves with the palace CLI, not before.
pub const mythos_chain = @import("memory-palace/mythos-chain.zig");
pub const archiform = @import("archiform.zig");
/// Golden-bytes constants (Blake3 pins + a few full-bytes hex pins). Exported
/// so `tools/export-golden-fixtures` can assert its freshly-encoded bytes
/// agree with the pinned constants instead of re-deriving them by hand — see
/// `fixtures/goldens/README.md` for why that matters during the Rust port.
pub const golden = @import("golden.zig");

pub const Stage = protocol.Stage;
pub const DreamBall = protocol.DreamBall;
pub const Look = protocol.Look;
pub const Feel = protocol.Feel;
pub const Act = protocol.Act;
pub const Asset = protocol.Asset;
pub const Skill = protocol.Skill;
pub const Fingerprint = fingerprint.Fingerprint;
pub const SigningKeys = signer.SigningKeys;

test {
    _ = protocol;
    _ = fingerprint;
    _ = base58;
    _ = dcbor;
    _ = envelope;
    _ = sealing;
    _ = json;
    _ = signer;
    _ = graph;
    _ = protocol_v2;
    _ = envelope_v2;
    _ = ml_dsa;
    _ = key_file;
    _ = identity_envelope;
    _ = archiform;
    _ = @import("golden.zig");
    // Palace memory utilities (S3.4) — exported as dreamball.mythos_chain
    _ = mythos_chain;
}
