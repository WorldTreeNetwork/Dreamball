//! Shared wasm-host failure-path helpers — Story 5.3 (AC1, AC2, AC3, AC5, AC6).
//!
//! Per D-032 and AC6, these helpers MUST live here (in `src/wasm-host/`),
//! not in a CLI-specific file, so they apply symmetrically to CLI,
//! dreamball-server, and in-renderer hosts.
//!
//! Three failure paths:
//!
//!   1. `verifyBlake3` — SEC4 / D-031 / AC1.
//!      Before instantiation, compute blake3(wasm_bytes) and compare to
//!      the manifest-declared fp. Abort and return structured event if
//!      mismatch. Only blake3 this sprint — no per-module signature check
//!      per D-031.
//!
//!   2. `verifyImports` — SEC1 / D-033 / AC2.
//!      Before instantiation, walk the wasm module's import table and
//!      check each (module, field) pair against the allowlist.
//!      Allowlist: `dreamball.{fp,encode_cbor,read_node,emit_action_envelope,now_ms}`.
//!      Any other import triggers rejection BEFORE any guest code runs.
//!
//!   3. `checkMemoryLimit` — NFR7 / AC3 / AC4 / AC5.
//!      Enforce initial pages ≤ max_mib and hard ceiling = 64 MiB.
//!      If the guest's declared initial memory exceeds the configured
//!      limit, abort before instantiation.

const std = @import("std");
const runtime = @import("runtime.zig");
const imports_mod = @import("imports.zig");

/// Default initial memory limit (NFR7): 16 MiB.
pub const DEFAULT_MEM_MIB: u32 = 16;
/// Hard ceiling (NFR7): 64 MiB. Values beyond this are rejected at CLI
/// parse time (AC4) and also enforced here defensively.
pub const HARD_CEILING_MIB: u32 = 64;

pub const PAGE_SIZE: u32 = 65536;

/// Structured failure event payload (NFR11 / AC7).
/// Emitted to stderr as one JSON line per `emitFailureEvent`.
pub const FailureEvent = union(enum) {
    fp_mismatch: struct {
        expected: [32]u8,
        actual: [32]u8,
        module_fp: [32]u8,
    },
    import_violation: struct {
        offending_module: []const u8,
        offending_name: []const u8,
        module_fp: [32]u8,
    },
    oom_trap: struct {
        module_fp: [32]u8,
        attempted_alloc_bytes: u64,
    },
};

/// Emit one JSON structured-log event to stderr (NFR11 / AC7).
/// Called by the host driver (main.zig) after a failure-path function
/// returns an error. The format matches Story 5.2 AC7's schema with
/// `outcome` taking the failure-mode value.
pub fn emitFailureEvent(
    allocator: std.mem.Allocator,
    write_stderr: fn ([]const u8) void,
    event: FailureEvent,
) !void {
    const line = switch (event) {
        .fp_mismatch => |e| blk: {
            const exp_hex: [64]u8 = std.fmt.bytesToHex(e.expected, .lower);
            const act_hex: [64]u8 = std.fmt.bytesToHex(e.actual, .lower);
            const mod_hex: [64]u8 = std.fmt.bytesToHex(e.module_fp, .lower);
            break :blk try std.fmt.allocPrint(allocator,
                "{{\"outcome\":\"fp_mismatch\",\"expected\":\"{s}\",\"actual\":\"{s}\",\"module_fp\":\"{s}\"}}\n",
                .{ exp_hex, act_hex, mod_hex },
            );
        },
        .import_violation => |e| blk: {
            const mod_hex: [64]u8 = std.fmt.bytesToHex(e.module_fp, .lower);
            break :blk try std.fmt.allocPrint(allocator,
                "{{\"outcome\":\"import_violation\",\"offending_import\":\"{s}.{s}\",\"module_fp\":\"{s}\"}}\n",
                .{ e.offending_module, e.offending_name, mod_hex },
            );
        },
        .oom_trap => |e| blk: {
            const mod_hex: [64]u8 = std.fmt.bytesToHex(e.module_fp, .lower);
            break :blk try std.fmt.allocPrint(allocator,
                "{{\"outcome\":\"trap\",\"trap_kind\":\"oom\",\"module_fp\":\"{s}\",\"attempted_alloc_bytes\":{d}}}\n",
                .{ mod_hex, e.attempted_alloc_bytes },
            );
        },
    };
    defer allocator.free(line);
    write_stderr(line);
}

/// AC1 / SEC4 / D-031: compute blake3(wasm_bytes) and compare to
/// `expected_fp`. Returns `true` if they match (instantiation may
/// proceed). Returns `false` if they do not match (caller should abort
/// and emit a `fp_mismatch` FailureEvent).
///
/// Only blake3 — no per-module signature check — per D-031.
pub fn verifyBlake3(wasm_bytes: []const u8, expected_fp: [32]u8) bool {
    var actual: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(wasm_bytes);
    hasher.final(&actual);
    return std.mem.eql(u8, &actual, &expected_fp);
}

/// Compute blake3(wasm_bytes) and return the digest. Convenience
/// helper used by callers that need the actual fp for event emission.
pub fn computeBlake3(wasm_bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(wasm_bytes);
    hasher.final(&digest);
    return digest;
}

/// AC2 / SEC1 / D-033: Walk the already-parsed module's import table
/// and check each (module, name) pair against the allowlist:
///   `dreamball.{fp, encode_cbor, read_node, emit_action_envelope, now_ms}`.
///
/// Returns `null` if all imports are allowed.
/// Returns the first offending import if any is outside the allowlist.
///
/// This is a static check on the parsed Module before any code runs.
pub fn verifyImports(module: *const runtime.Module) ?runtime.Import {
    for (module.imports) |imp| {
        if (!isAllowedImport(imp.module, imp.name)) {
            return imp;
        }
    }
    return null;
}

fn isAllowedImport(module_name: []const u8, name: []const u8) bool {
    if (!std.mem.eql(u8, module_name, "dreamball")) return false;
    for (imports_mod.IMPORT_NAMES) |allowed| {
        if (std.mem.eql(u8, name, allowed)) return true;
    }
    return false;
}

/// AC3 / AC4 / NFR7: check that the module's declared initial memory
/// does not exceed `max_mib` MiB. Also enforces the hard ceiling of
/// 64 MiB regardless of the configured limit.
///
/// Returns the effective byte count if within limits, or an error:
///   - `error.MemoryLimitExceeded` if initial pages exceed `max_mib`.
///   - `error.MemoryLimitExceeded` if `max_mib > HARD_CEILING_MIB`.
pub fn checkMemoryLimit(module: *const runtime.Module, max_mib: u32) error{MemoryLimitExceeded}!u32 {
    const effective_max: u32 = @min(max_mib, HARD_CEILING_MIB);
    const max_bytes: u32 = effective_max *| (1024 * 1024);
    const max_pages: u32 = max_bytes / PAGE_SIZE;
    // Modules with memory_initial_pages == 0 get one page by default
    // (see runtime.Instance.init); that's always within limits.
    const initial_pages = module.memory_initial_pages;
    if (initial_pages > max_pages) {
        return error.MemoryLimitExceeded;
    }
    const initial_bytes = if (initial_pages == 0) PAGE_SIZE else initial_pages * PAGE_SIZE;
    return initial_bytes;
}

test "verifyBlake3 matches" {
    const data = "hello wasm";
    var expected: [32]u8 = undefined;
    var h = std.crypto.hash.Blake3.init(.{});
    h.update(data);
    h.final(&expected);
    try std.testing.expect(verifyBlake3(data, expected));
}

test "verifyBlake3 mismatch" {
    const data = "hello wasm";
    const wrong: [32]u8 = [_]u8{0xAB} ** 32;
    try std.testing.expect(!verifyBlake3(data, wrong));
}

test "computeBlake3 consistent" {
    const data = "dreamball-test";
    const a = computeBlake3(data);
    const b = computeBlake3(data);
    try std.testing.expectEqualSlices(u8, &a, &b);
}

test "isAllowedImport only permits dreamball.* names" {
    try std.testing.expect(isAllowedImport("dreamball", "fp"));
    try std.testing.expect(isAllowedImport("dreamball", "encode_cbor"));
    try std.testing.expect(isAllowedImport("dreamball", "read_node"));
    try std.testing.expect(isAllowedImport("dreamball", "emit_action_envelope"));
    try std.testing.expect(isAllowedImport("dreamball", "now_ms"));
    try std.testing.expect(!isAllowedImport("dreamball", "malicious_function"));
    try std.testing.expect(!isAllowedImport("env", "malicious_function"));
    try std.testing.expect(!isAllowedImport("wasi_snapshot_preview1", "fd_write"));
}

test "checkMemoryLimit default 16 MiB" {
    // Build a minimal module with 256 pages (16 MiB) — should pass.
    var mod = runtime.Module{
        .allocator = std.testing.allocator,
        .bytes_owned = &.{},
        .types = &.{},
        .imports = &.{},
        .function_type_indices = &.{},
        .memory_initial_pages = 256, // 256 * 64 KiB = 16 MiB
        .exports = &.{},
        .bodies = &.{},
        .data = &.{},
    };
    const bytes = try checkMemoryLimit(&mod, DEFAULT_MEM_MIB);
    try std.testing.expectEqual(@as(u32, 16 * 1024 * 1024), bytes);
}

test "checkMemoryLimit rejects over 64 MiB hard ceiling" {
    var mod = runtime.Module{
        .allocator = std.testing.allocator,
        .bytes_owned = &.{},
        .types = &.{},
        .imports = &.{},
        .function_type_indices = &.{},
        .memory_initial_pages = 1025, // 65 MiB — exceeds hard ceiling
        .exports = &.{},
        .bodies = &.{},
        .data = &.{},
    };
    try std.testing.expectError(error.MemoryLimitExceeded, checkMemoryLimit(&mod, HARD_CEILING_MIB + 1));
}

test "checkMemoryLimit rejects over configured limit" {
    var mod = runtime.Module{
        .allocator = std.testing.allocator,
        .bytes_owned = &.{},
        .types = &.{},
        .imports = &.{},
        .function_type_indices = &.{},
        .memory_initial_pages = 300, // ~18.75 MiB — exceeds 16 MiB default
        .exports = &.{},
        .bodies = &.{},
        .data = &.{},
    };
    try std.testing.expectError(error.MemoryLimitExceeded, checkMemoryLimit(&mod, DEFAULT_MEM_MIB));
}
