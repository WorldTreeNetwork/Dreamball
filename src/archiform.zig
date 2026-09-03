//! Story 2.3 / FR5 / D-017 — archiform_fp implicit-binding constants.
//!
//! Per AC2: sprint-001 envelopes lacking `archiform-fp` decode by
//! implicitly binding to `dreamball/memory-palace@0.1.0`. The implicit
//! fp is computed once at compile time over the canonical bytes of
//! `schemas/memory-palace-0.1.0.json` (the vendored, pinned schema).
//!
//! Per Technical Notes (Story 2.3): "the implicit-binding default is
//! computed once at decoder init: MEMORY_PALACE_IMPLICIT_FP =
//! blake3(readFile('schemas/memory-palace-0.1.0.json')) — cached, not
//! recomputed per decode." `comptime` is the strongest cache.
//!
//! D-017 / TC8: archiform_fp is content-addressing — the schema body's
//! blake3, vendored, must equal `schemas/.pins/memory-palace-0.1.0.fp`.

const std = @import("std");

/// Canonical bytes of `schemas/memory-palace-0.1.0.json` baked into the
/// binary at compile time. The `src/schemas` symlink (→ `schemas/`) keeps
/// the embed path inside the Zig package root; without the symlink Zig
/// rejects `../schemas/...` paths under "embed of file outside package
/// path." Same pattern as `src/recrypt-identity-fixtures`.
pub const MEMORY_PALACE_SCHEMA_BYTES: []const u8 =
    @embedFile("schemas/memory-palace-0.1.0.json");

/// blake3 of the canonical Memory Palace schema bytes — the implicit
/// archiform_fp for sprint-001 back-compat (FR5 / Story 2.3 AC2). Computed
/// at comptime so the cost is paid in the build, not at decode time.
pub const MEMORY_PALACE_IMPLICIT_FP: [32]u8 = blk: {
    @setEvalBranchQuota(1_000_000);
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(MEMORY_PALACE_SCHEMA_BYTES, &hash, .{});
    break :blk hash;
};

/// AC4 (drift detection) — structured error reported when two envelopes
/// for the same ball declare different `archiform_fp` values. The verifier
/// consumes this to short-circuit before any signature check.
pub const DriftReport = struct {
    /// Genesis-recorded fp (first revision encountered).
    genesis: [32]u8,
    /// Conflicting fp on a subsequent revision.
    observed: [32]u8,

    /// Format the structured error into the caller's buffer. Returns the
    /// number of bytes written. Format is stable so CI scripts can grep:
    ///   archiform-fp drift: genesis=<hex64> observed=<hex64>
    /// Buffer must be at least 165 bytes (28 + 64 + 10 + 64 = 166 with slack).
    pub fn format(self: DriftReport, buf: []u8) ![]const u8 {
        const charset = "0123456789abcdef";
        const prefix = "archiform-fp drift: genesis=";
        const sep = " observed=";
        const total = prefix.len + 64 + sep.len + 64;
        if (buf.len < total) return error.NoSpaceLeft;
        var i: usize = 0;
        @memcpy(buf[i .. i + prefix.len], prefix);
        i += prefix.len;
        for (self.genesis) |b| {
            buf[i] = charset[b >> 4];
            buf[i + 1] = charset[b & 0xF];
            i += 2;
        }
        @memcpy(buf[i .. i + sep.len], sep);
        i += sep.len;
        for (self.observed) |b| {
            buf[i] = charset[b >> 4];
            buf[i + 1] = charset[b & 0xF];
            i += 2;
        }
        return buf[0..i];
    }
};

/// Resolve an envelope's archiform_fp via the implicit-binding rule
/// (AC2). Pass `null` if the field was absent on the wire; receive the
/// implicit Memory Palace fp.
pub fn resolveImplicit(on_wire: ?[32]u8) [32]u8 {
    return on_wire orelse MEMORY_PALACE_IMPLICIT_FP;
}

/// AC4 — compare two resolved fps. Returns null if equal (no drift),
/// or a `DriftReport` documenting the mismatch. Callers (dreamball verify,
/// store consistency checks) plug this in wherever genesis + subsequent
/// envelopes for the same ball are loaded.
pub fn detectDrift(genesis: [32]u8, observed: [32]u8) ?DriftReport {
    if (std.mem.eql(u8, &genesis, &observed)) return null;
    return .{ .genesis = genesis, .observed = observed };
}

test "AC4 detectDrift returns null when equal" {
    const fp = MEMORY_PALACE_IMPLICIT_FP;
    try std.testing.expect(detectDrift(fp, fp) == null);
}

test "AC4 detectDrift reports both fps on mismatch" {
    var alt = MEMORY_PALACE_IMPLICIT_FP;
    alt[0] ^= 0xFF;
    const report = detectDrift(MEMORY_PALACE_IMPLICIT_FP, alt) orelse {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expectEqualSlices(u8, &MEMORY_PALACE_IMPLICIT_FP, &report.genesis);
    try std.testing.expectEqualSlices(u8, &alt, &report.observed);

    // Format check: stable string form contains both hexes.
    var buf: [256]u8 = undefined;
    const written = try report.format(&buf);
    try std.testing.expect(std.mem.indexOf(u8, written, "archiform-fp drift:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "genesis=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "observed=") != null);
}

test "AC2 resolveImplicit substitutes the Memory Palace fp on null" {
    try std.testing.expectEqualSlices(u8, &MEMORY_PALACE_IMPLICIT_FP, &resolveImplicit(null));
    var custom: [32]u8 = [_]u8{0x42} ** 32;
    try std.testing.expectEqualSlices(u8, &custom, &resolveImplicit(custom));
}

test "MEMORY_PALACE_IMPLICIT_FP matches vendored pin" {
    const pin_bytes = @embedFile("schemas/.pins/memory-palace-0.1.0.fp");
    // Pin is plain hex, no trailing newline (D-029 Option A).
    try std.testing.expectEqual(@as(usize, 64), pin_bytes.len);

    var fp_hex: [64]u8 = undefined;
    const charset = "0123456789abcdef";
    for (MEMORY_PALACE_IMPLICIT_FP, 0..) |b, i| {
        fp_hex[i * 2] = charset[b >> 4];
        fp_hex[i * 2 + 1] = charset[b & 0xF];
    }
    try std.testing.expectEqualStrings(pin_bytes, &fp_hex);
}
