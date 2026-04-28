//! Zig-level unit tests for Story 5.3 failure paths (AC1, AC2, AC3, AC5, AC8).
//!
//! These tests exercise `failure_paths.zig` helpers + the three new guest
//! builders (`buildBadImportGuest`, `buildOomGuest`, `buildProdGuest`
//! with a wrong fp) end-to-end through the runtime, mirroring the shape
//! of `imports_test.zig`.

const std = @import("std");
const runtime = @import("runtime.zig");
const imports_mod = @import("imports.zig");
const failure = @import("failure_paths.zig");
const guest = @import("build_guest.zig");

// ─────────────────────────────────────────────────────────────────────────
// AC1: verifyBlake3 — fp_mismatch aborts before instantiation
// ─────────────────────────────────────────────────────────────────────────

test "AC1: fp_mismatch rejected before any guest code runs" {
    const allocator = std.testing.allocator;

    const seed: [32]u8 = .{0x42} ** 32;
    const kp = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);
    var host = imports_mod.Host.init(allocator, kp.secret_key.toBytes(), &.{});
    defer host.deinit();

    const wasm_bytes = try guest.buildProdGuest(allocator);
    defer allocator.free(wasm_bytes);

    // Deliberately-wrong fp (all 0xAB).
    const wrong_fp: [32]u8 = [_]u8{0xAB} ** 32;
    host.beginInvocation("test-fp-mismatch", [_]u8{0} ** 32, [_]u8{0} ** 32, wrong_fp);

    // verifyBlake3 should reject the bytes.
    const ok = failure.verifyBlake3(wasm_bytes, host.module_fp);
    try std.testing.expect(!ok);

    // The actual fp should differ from the wrong one.
    const actual = failure.computeBlake3(wasm_bytes);
    try std.testing.expect(!std.mem.eql(u8, &actual, &wrong_fp));
}

test "AC1: fp_match passes verification" {
    const allocator = std.testing.allocator;

    const wasm_bytes = try guest.buildProdGuest(allocator);
    defer allocator.free(wasm_bytes);

    const correct_fp = failure.computeBlake3(wasm_bytes);
    try std.testing.expect(failure.verifyBlake3(wasm_bytes, correct_fp));
}

// ─────────────────────────────────────────────────────────────────────────
// AC2: verifyImports — import-violation rejected before instantiation
// ─────────────────────────────────────────────────────────────────────────

test "AC2: bad-import guest rejected before instantiation" {
    const allocator = std.testing.allocator;

    const bad_bytes = try guest.buildBadImportGuest(allocator);
    defer allocator.free(bad_bytes);

    var module = try runtime.parse(allocator, bad_bytes);
    defer module.deinit();

    // Import-violation check finds the offending import.
    const offender = failure.verifyImports(&module);
    try std.testing.expect(offender != null);
    try std.testing.expectEqualStrings("env", offender.?.module);
    try std.testing.expectEqualStrings("malicious_function", offender.?.name);
}

test "AC2: valid dreamball.* guest passes import check" {
    const allocator = std.testing.allocator;

    const good_bytes = try guest.buildProdGuest(allocator);
    defer allocator.free(good_bytes);

    var module = try runtime.parse(allocator, good_bytes);
    defer module.deinit();

    const offender = failure.verifyImports(&module);
    try std.testing.expect(offender == null);
}

// ─────────────────────────────────────────────────────────────────────────
// AC3: checkMemoryLimit — default 16 MiB / hard ceiling 64 MiB
// ─────────────────────────────────────────────────────────────────────────

test "AC3: prod guest (1 page) passes 16 MiB default limit" {
    const allocator = std.testing.allocator;

    const good_bytes = try guest.buildProdGuest(allocator);
    defer allocator.free(good_bytes);

    var module = try runtime.parse(allocator, good_bytes);
    defer module.deinit();

    // 1 page = 64 KiB — well within 16 MiB.
    const bytes = try failure.checkMemoryLimit(&module, failure.DEFAULT_MEM_MIB);
    try std.testing.expect(bytes <= failure.DEFAULT_MEM_MIB * 1024 * 1024);
}

test "AC3/NFR7: OOM guest (1025 pages = 65 MiB) rejected at hard ceiling" {
    const allocator = std.testing.allocator;

    // 1025 pages * 64 KiB = 65 MiB — exceeds 64 MiB hard ceiling.
    const oom_bytes = try guest.buildOomGuest(allocator, 1025);
    defer allocator.free(oom_bytes);

    var module = try runtime.parse(allocator, oom_bytes);
    defer module.deinit();

    // Even if caller passes 64 MiB, 1025 pages exceed it.
    try std.testing.expectError(
        error.MemoryLimitExceeded,
        failure.checkMemoryLimit(&module, failure.HARD_CEILING_MIB),
    );
}

test "AC4: configurable limit respected" {
    const allocator = std.testing.allocator;

    // 300 pages = ~18.75 MiB — exceeds 16 MiB but within 32 MiB.
    const mid_bytes = try guest.buildOomGuest(allocator, 300);
    defer allocator.free(mid_bytes);

    var module = try runtime.parse(allocator, mid_bytes);
    defer module.deinit();

    // Rejected at 16 MiB default.
    try std.testing.expectError(
        error.MemoryLimitExceeded,
        failure.checkMemoryLimit(&module, failure.DEFAULT_MEM_MIB),
    );

    // Allowed at 32 MiB.
    const bytes = try failure.checkMemoryLimit(&module, 32);
    try std.testing.expect(bytes > 0);
}

// ─────────────────────────────────────────────────────────────────────────
// AC6: grep audit helper — failure helpers must be in src/wasm-host/
// This is enforced by the build.zig grep-audit step; we assert the
// symbol names here so a rename can't silently drop the AC6 grep target.
// ─────────────────────────────────────────────────────────────────────────

test "AC6: failure helper symbols exist in failure_paths.zig" {
    // If these comptime evaluations compile, the symbols exist.
    const _vb = failure.verifyBlake3;
    const _vi = failure.verifyImports;
    const _cm = failure.checkMemoryLimit;
    _ = _vb;
    _ = _vi;
    _ = _cm;
}
