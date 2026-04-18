//! Graph integrity for DreamBall containment.
//!
//! Two levels of check:
//!
//!  1. `validateSelf(db)` — cheap, local. Rejects any DreamBall whose own
//!     fingerprint appears in its own `contains` list (self-containment is
//!     meaningless and always a bug).
//!
//!  2. `validateFleet(fleet)` — depth-first walk across a collection of
//!     DreamBalls. Rejects any `contains` cycle. Non-transitive
//!     (`derived-from` edges are documented inspiration; they don't
//!     participate in cycle checking because a mutual "inspired by" is fine).
//!
//! See docs/VISION.md §3 for why the containment graph must be acyclic:
//! a fractal self-similar structure relies on being a DAG so that every
//! descendant is renderable in finite time without re-entering its ancestors.

const std = @import("std");
const Allocator = std.mem.Allocator;

const protocol = @import("protocol.zig");
const fingerprint = @import("fingerprint.zig");

pub const Error = error{
    SelfContainment,
    ContainmentCycle,
    UnresolvedFingerprint,
    OutOfMemory,
};

pub fn validateSelf(db: protocol.DreamBall) Error!void {
    const my_fp = db.fingerprint();
    for (db.contains) |fp| {
        if (std.mem.eql(u8, &fp.bytes, &my_fp.bytes)) return Error.SelfContainment;
    }
}

/// A fleet is an unordered list of DreamBalls — the validator builds a
/// fingerprint → index map so it can follow `contains` edges.
pub const Fleet = struct {
    members: []const protocol.DreamBall,

    pub fn findByFingerprint(self: Fleet, fp: fingerprint.Fingerprint) ?usize {
        for (self.members, 0..) |m, i| {
            if (std.mem.eql(u8, &m.fingerprint().bytes, &fp.bytes)) return i;
        }
        return null;
    }
};

const Color = enum(u8) { white, gray, black };

pub fn validateFleet(allocator: Allocator, fleet: Fleet) Error!void {
    const n = fleet.members.len;
    if (n == 0) return;

    // First: every member must pass self-validation.
    for (fleet.members) |m| try validateSelf(m);

    // DFS with three colors per node: white (unvisited), gray (on stack),
    // black (finished). A gray→gray edge during DFS is a cycle.
    const colors = try allocator.alloc(Color, n);
    defer allocator.free(colors);
    @memset(colors, .white);

    for (fleet.members, 0..) |_, i| {
        if (colors[i] != .white) continue;
        try dfsVisit(fleet, i, colors);
    }
}

fn dfsVisit(fleet: Fleet, idx: usize, colors: []Color) Error!void {
    colors[idx] = .gray;
    defer colors[idx] = .black;

    const node = fleet.members[idx];
    for (node.contains) |fp| {
        const child_idx = fleet.findByFingerprint(fp) orelse return Error.UnresolvedFingerprint;
        switch (colors[child_idx]) {
            .white => try dfsVisit(fleet, child_idx, colors),
            .gray => return Error.ContainmentCycle,
            .black => {},
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "validateSelf: self-containment rejected" {
    const pk: [32]u8 = [_]u8{0xAA} ** 32;
    const own_fp = fingerprint.Fingerprint.fromEd25519(pk);
    const contains = [_]fingerprint.Fingerprint{own_fp};
    const db = protocol.DreamBall{
        .stage = .dreamball,
        .identity = pk,
        .genesis_hash = [_]u8{0} ** 32,
        .contains = &contains,
    };
    try std.testing.expectError(Error.SelfContainment, validateSelf(db));
}

test "validateSelf: normal containment accepted" {
    const pk: [32]u8 = [_]u8{0xAA} ** 32;
    const other_fp = fingerprint.Fingerprint.fromEd25519([_]u8{0xBB} ** 32);
    const contains = [_]fingerprint.Fingerprint{other_fp};
    const db = protocol.DreamBall{
        .stage = .dreamball,
        .identity = pk,
        .genesis_hash = [_]u8{0} ** 32,
        .contains = &contains,
    };
    try validateSelf(db);
}

test "validateFleet: acyclic DAG accepted" {
    const allocator = std.testing.allocator;
    const a_pk: [32]u8 = [_]u8{1} ** 32;
    const b_pk: [32]u8 = [_]u8{2} ** 32;
    const c_pk: [32]u8 = [_]u8{3} ** 32;
    const b_fp = fingerprint.Fingerprint.fromEd25519(b_pk);
    const c_fp = fingerprint.Fingerprint.fromEd25519(c_pk);

    const a_contains = [_]fingerprint.Fingerprint{ b_fp, c_fp };
    const b_contains = [_]fingerprint.Fingerprint{c_fp};
    const a = protocol.DreamBall{
        .stage = .dreamball,
        .identity = a_pk,
        .genesis_hash = [_]u8{0} ** 32,
        .contains = &a_contains,
    };
    const b = protocol.DreamBall{
        .stage = .dreamball,
        .identity = b_pk,
        .genesis_hash = [_]u8{0} ** 32,
        .contains = &b_contains,
    };
    const c = protocol.DreamBall{
        .stage = .dreamball,
        .identity = c_pk,
        .genesis_hash = [_]u8{0} ** 32,
    };
    const members = [_]protocol.DreamBall{ a, b, c };
    try validateFleet(allocator, .{ .members = &members });
}

test "validateFleet: cycle rejected" {
    const allocator = std.testing.allocator;
    const a_pk: [32]u8 = [_]u8{1} ** 32;
    const b_pk: [32]u8 = [_]u8{2} ** 32;
    const a_fp = fingerprint.Fingerprint.fromEd25519(a_pk);
    const b_fp = fingerprint.Fingerprint.fromEd25519(b_pk);

    const a_contains = [_]fingerprint.Fingerprint{b_fp};
    const b_contains = [_]fingerprint.Fingerprint{a_fp};
    const a = protocol.DreamBall{
        .stage = .dreamball,
        .identity = a_pk,
        .genesis_hash = [_]u8{0} ** 32,
        .contains = &a_contains,
    };
    const b = protocol.DreamBall{
        .stage = .dreamball,
        .identity = b_pk,
        .genesis_hash = [_]u8{0} ** 32,
        .contains = &b_contains,
    };
    const members = [_]protocol.DreamBall{ a, b };
    try std.testing.expectError(Error.ContainmentCycle, validateFleet(allocator, .{ .members = &members }));
}

test "validateFleet: unresolved fingerprint rejected" {
    const allocator = std.testing.allocator;
    const a_pk: [32]u8 = [_]u8{1} ** 32;
    const ghost_fp = fingerprint.Fingerprint.fromEd25519([_]u8{9} ** 32);
    const a_contains = [_]fingerprint.Fingerprint{ghost_fp};
    const a = protocol.DreamBall{
        .stage = .dreamball,
        .identity = a_pk,
        .genesis_hash = [_]u8{0} ** 32,
        .contains = &a_contains,
    };
    const members = [_]protocol.DreamBall{a};
    try std.testing.expectError(Error.UnresolvedFingerprint, validateFleet(allocator, .{ .members = &members }));
}
