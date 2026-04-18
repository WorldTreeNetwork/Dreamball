//! DreamBall — a signed, evolvable NFT-like container for look/feel/act.
//! See docs/PROTOCOL.md for the wire format.

const std = @import("std");

pub const protocol = @import("protocol.zig");
pub const protocol_v2 = @import("protocol_v2.zig");
pub const fingerprint = @import("fingerprint.zig");
pub const base58 = @import("base58.zig");
pub const cbor = @import("cbor.zig");
pub const envelope = @import("envelope.zig");
pub const envelope_v2 = @import("envelope_v2.zig");
pub const sealing = @import("sealing.zig");
pub const json = @import("json.zig");
pub const signer = @import("signer.zig");
pub const graph = @import("graph.zig");

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
    _ = cbor;
    _ = envelope;
    _ = sealing;
    _ = json;
    _ = signer;
    _ = graph;
    _ = protocol_v2;
    _ = envelope_v2;
    _ = @import("golden.zig");
}
