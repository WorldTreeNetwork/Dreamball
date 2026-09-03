//! Story 5.3 AC8 failure-path test driver.
//!
//! A standalone binary (built by `zig build wasm-host-failure-test`)
//! that exercises the three failure modes from failure_paths.zig and
//! emits one JSON object per scenario to stdout. TypeScript fixture
//! tests under `tests/wasm/host/` invoke this binary and assert on
//! the JSON output.
//!
//! Exit code 0 means all three failure modes were correctly triggered
//! (the host rejected as expected). Non-zero means a failure mode
//! was not triggered when it should have been.
//!
//! Output (one JSON object per line):
//!   {"scenario":"fp_mismatch","outcome":"fp_mismatch","expected":"<hex>","actual":"<hex>"}
//!   {"scenario":"import_violation","outcome":"import_violation","offending_import":"env.malicious_function"}
//!   {"scenario":"oom","outcome":"memory_limit_exceeded","initial_pages":1025,"max_mib":64}

const std = @import("std");
const runtime = @import("runtime.zig");
const imports_mod = @import("imports.zig");
const failure = @import("failure_paths.zig");
const guest = @import("build_guest.zig");

fn iface() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn writeStdout(bytes: []const u8) void {
    var buf: [8192]u8 = undefined;
    var w = std.Io.File.stdout().writer(iface(), &buf);
    w.interface.writeAll(bytes) catch return;
    w.interface.flush() catch return;
}

fn writeStderr(bytes: []const u8) void {
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stderr().writer(iface(), &buf);
    w.interface.writeAll(bytes) catch return;
    w.interface.flush() catch return;
}

fn printFmt(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStdout(s);
}

fn printErrFmt(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStderr(s);
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;

    // ── Scenario 1: fp_mismatch ────────────────────────────────────────
    // Build the prod guest, compute the correct fp, then deliberately
    // pass a wrong fp. verifyBlake3 must return false.
    {
        const wasm_bytes = try guest.buildProdGuest(gpa);
        defer gpa.free(wasm_bytes);

        const correct_fp = failure.computeBlake3(wasm_bytes);
        const wrong_fp: [32]u8 = [_]u8{0xAB} ** 32;

        // Correct fp must match.
        if (!failure.verifyBlake3(wasm_bytes, correct_fp)) {
            try printErrFmt(gpa, "FAIL: fp_mismatch scenario — correct fp was rejected\n", .{});
            return 1;
        }

        // Wrong fp must mismatch.
        if (failure.verifyBlake3(wasm_bytes, wrong_fp)) {
            try printErrFmt(gpa, "FAIL: fp_mismatch scenario — wrong fp was accepted\n", .{});
            return 2;
        }

        const actual = failure.computeBlake3(wasm_bytes);
        const exp_hex: [64]u8 = std.fmt.bytesToHex(wrong_fp, .lower);
        const act_hex: [64]u8 = std.fmt.bytesToHex(actual, .lower);
        try printFmt(gpa,
            "{{\"scenario\":\"fp_mismatch\",\"outcome\":\"fp_mismatch\",\"expected\":\"{s}\",\"actual\":\"{s}\"}}\n",
            .{ exp_hex, act_hex },
        );
    }

    // ── Scenario 2: import_violation ──────────────────────────────────
    // Build a guest importing `env.malicious_function`. verifyImports
    // must return the offending import.
    {
        const bad_bytes = try guest.buildBadImportGuest(gpa);
        defer gpa.free(bad_bytes);

        var bad_module = try runtime.parse(gpa, bad_bytes);
        defer bad_module.deinit();

        const offender = failure.verifyImports(&bad_module);
        if (offender == null) {
            try printErrFmt(gpa, "FAIL: import_violation scenario — bad import was not detected\n", .{});
            return 3;
        }

        const mod_fp = failure.computeBlake3(bad_bytes);
        const mod_hex: [64]u8 = std.fmt.bytesToHex(mod_fp, .lower);
        try printFmt(gpa,
            "{{\"scenario\":\"import_violation\",\"outcome\":\"import_violation\",\"offending_import\":\"{s}.{s}\",\"module_fp\":\"{s}\"}}\n",
            .{ offender.?.module, offender.?.name, mod_hex },
        );
    }

    // ── Scenario 3: OOM / memory limit exceeded ────────────────────────
    // Build a guest with 1025 pages (65 MiB). checkMemoryLimit at the
    // 64 MiB hard ceiling must return MemoryLimitExceeded.
    {
        // 1025 pages * 64 KiB = 65 MiB — exceeds 64 MiB hard ceiling.
        const oom_pages: u32 = 1025;
        const oom_bytes = try guest.buildOomGuest(gpa, oom_pages);
        defer gpa.free(oom_bytes);

        var oom_module = try runtime.parse(gpa, oom_bytes);
        defer oom_module.deinit();

        const result = failure.checkMemoryLimit(&oom_module, failure.HARD_CEILING_MIB);
        if (result) |_| {
            try printErrFmt(gpa, "FAIL: oom scenario — oversized guest was not rejected\n", .{});
            return 4;
        } else |err| {
            if (err != error.MemoryLimitExceeded) {
                try printErrFmt(gpa, "FAIL: oom scenario — unexpected error: {}\n", .{err});
                return 5;
            }
        }

        const attempted: u64 = @as(u64, oom_pages) * failure.PAGE_SIZE;
        try printFmt(gpa,
            "{{\"scenario\":\"oom\",\"outcome\":\"memory_limit_exceeded\",\"initial_pages\":{d},\"max_mib\":{d},\"attempted_alloc_bytes\":{d}}}\n",
            .{ oom_pages, failure.HARD_CEILING_MIB, attempted },
        );
    }

    try printFmt(gpa, "{{\"summary\":\"all 3 failure scenarios triggered correctly\"}}\n", .{});
    return 0;
}
