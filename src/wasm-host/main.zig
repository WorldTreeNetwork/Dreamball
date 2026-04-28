//! Production wasm-host driver — Story 5.2 promotion of the Story 5.1
//! spike. The driver:
//!
//!   1. Builds a guest module that imports each of the 5
//!      `dreamball.*` imports (D-033). The guest is a hand-authored
//!      wasm artefact built by `build_guest.zig` (the production
//!      analog of the spike's `build_hello.zig`).
//!   2. Instantiates against the production import surface
//!      (`imports.zig.bindAll`).
//!   3. Drives the action-invocation lifecycle:
//!      `Host.beginInvocation` → invoke `_start` → emit NFR11
//!      structured-log JSON event → record AC6 timing.
//!   4. Runs the AC6 perf harness — 100 trivial invocations,
//!      reports p95 ≤ 50 ms (M-series Mac baseline).
//!   5. Surfaces non-zero exit on any AC failure (no silent
//!      substitutions, per `feedback_dreamball_ac_scope_retreat`).
//!
//! Output schema (parsed by CI / smoke gates):
//!
//!   wasm-host: invocation ok action=mint module_fp=… emit_count=1 …
//!   wasm-host: AC6 p50=… p95=… max=… budget=50ms
//!
//! Per D-032 the source compiles for both CLI (today) and browser
//! (sprint-003). All platform-shimmed I/O lives in this file (the
//! library code at `imports.zig` and `runtime.zig` stays platform-pure).

const std = @import("std");
const runtime = @import("runtime.zig");
const imports_mod = @import("imports.zig");
const guest = @import("build_guest.zig");

/// AC6 / NFR3 budget: ≤ 50 ms p95 on M-series Mac for a trivial action.
const ac6_p95_budget_ms: u64 = 50;

fn iface() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn writeStream(file: std.Io.File, bytes: []const u8) void {
    var buf: [4096]u8 = undefined;
    var w = file.writer(iface(), &buf);
    w.interface.writeAll(bytes) catch return;
    w.interface.flush() catch return;
}

fn writeStdout(bytes: []const u8) void {
    writeStream(std.Io.File.stdout(), bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeStream(std.Io.File.stderr(), bytes);
}

/// NFR11 / AC7 structured event. Emitted to stderr as one JSON object
/// per invocation. Fields are byte-exact to the AC: `action_name`,
/// `actor_fp`, `archiform_fp`, `module_fp`, `duration_ms`, `emit_count`,
/// `outcome`. Hex encoding is canonical lower-case.
fn emitInvocationEvent(
    allocator: std.mem.Allocator,
    host: *const imports_mod.Host,
    duration_ms: u64,
    outcome: imports_mod.Outcome,
) !void {
    const actor_hex: [64]u8 = std.fmt.bytesToHex(host.actor_fp, .lower);
    const archiform_hex: [64]u8 = std.fmt.bytesToHex(host.archiform_fp, .lower);
    const module_hex: [64]u8 = std.fmt.bytesToHex(host.module_fp, .lower);

    const line = try std.fmt.allocPrint(allocator,
        "{{\"action_name\":\"{s}\",\"actor_fp\":\"{s}\",\"archiform_fp\":\"{s}\",\"module_fp\":\"{s}\",\"duration_ms\":{d},\"emit_count\":{d},\"outcome\":\"{s}\"}}\n",
        .{
            host.action_name,
            actor_hex,
            archiform_hex,
            module_hex,
            duration_ms,
            host.emit_count,
            imports_mod.outcomeName(outcome),
        },
    );
    defer allocator.free(line);
    writeStderr(line);
}

/// Run a single invocation through the host: parse + instantiate +
/// invokeStart, capturing duration and outcome. The caller emits the
/// NFR11 structured event from the returned data.
const InvocationResult = struct {
    duration_ms: u64,
    outcome: imports_mod.Outcome,
};

fn invokeOnce(
    allocator: std.mem.Allocator,
    host: *imports_mod.Host,
    wasm_bytes: []const u8,
    bindings: []const runtime.ImportBinding,
) !InvocationResult {
    const t_start = std.Io.Clock.Timestamp.now(iface(), std.Io.Clock.awake);
    var module = runtime.parse(allocator, wasm_bytes) catch |e| {
        return .{
            .duration_ms = elapsedMs(t_start),
            .outcome = if (e == runtime.Error.UnknownImport) .import_violation else .trap,
        };
    };
    defer module.deinit();

    var instance = runtime.Instance.init(allocator, &module, .{
        .imports = bindings,
        .host_context = host,
    }) catch |e| {
        return .{
            .duration_ms = elapsedMs(t_start),
            .outcome = if (e == runtime.Error.UnknownImport) .import_violation else .trap,
        };
    };
    defer instance.deinit();

    // The host scratch region begins at byte 0 of guest linear memory
    // for sprint-002. Future stories that author Zig→wasm guests with
    // their own bump allocator will move this; the location is
    // host-set, not part of the import contract.
    host.attach(0, 65536);

    instance.invokeStart() catch return .{
        .duration_ms = elapsedMs(t_start),
        .outcome = .trap,
    };

    return .{ .duration_ms = elapsedMs(t_start), .outcome = .ok };
}

fn elapsedMs(t_start: std.Io.Clock.Timestamp) u64 {
    const t_end = std.Io.Clock.Timestamp.now(iface(), std.Io.Clock.awake);
    const ns = t_start.durationTo(t_end).raw.nanoseconds;
    if (ns < 0) return 0;
    return @intCast(@divTrunc(ns, std.time.ns_per_ms));
}

fn percentile(samples: []u64, p: f64) u64 {
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    if (samples.len == 0) return 0;
    const idx_f = @as(f64, @floatFromInt(samples.len - 1)) * p;
    const idx: usize = @intFromFloat(@round(idx_f));
    return samples[idx];
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;

    // Build the production guest. It imports each of the 5
    // `dreamball.*` imports and exercises one of them in `_start`
    // (calling `dreamball.emit_action_envelope` is the canonical AC4
    // path; the per-import test driver covers the others).
    const wasm_bytes = try guest.buildProdGuest(gpa);
    defer gpa.free(wasm_bytes);

    // Deterministic keypair for the host (sprint-002 trusted-by-default
    // per SEC5; sprint-003 wires this from the projection layer).
    const seed: [32]u8 = .{0x42} ** 32;
    const kp = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);
    const keypair_bytes = kp.secret_key.toBytes();

    var host = imports_mod.Host.init(gpa, keypair_bytes, &.{});
    defer host.deinit();

    // ---------------- AC1 + AC4: single happy-path invocation ----------------
    const bindings = imports_mod.bindAll();
    const action_name = "wasm-host-self-test";
    var actor_fp: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update("actor:wasm-host-self-test");
    hasher.final(&actor_fp);
    var archiform_fp: [32]u8 = undefined;
    var ah = std.crypto.hash.Blake3.init(.{});
    ah.update("archiform:dreamball/sprint-002");
    ah.final(&archiform_fp);
    var module_fp: [32]u8 = undefined;
    var mh = std.crypto.hash.Blake3.init(.{});
    mh.update(wasm_bytes);
    mh.final(&module_fp);

    host.beginInvocation(action_name, actor_fp, archiform_fp, module_fp);

    const result = try invokeOnce(gpa, &host, wasm_bytes, &bindings);
    try emitInvocationEvent(gpa, &host, result.duration_ms, result.outcome);

    if (result.outcome != .ok) {
        try printStderrFmt(gpa, "wasm-host: BLOCKER — initial invocation outcome={s}\n", .{
            imports_mod.outcomeName(result.outcome),
        });
        return 2;
    }
    if (host.emit_count == 0) {
        try printStderrFmt(gpa, "wasm-host: BLOCKER — guest did not call emit_action_envelope\n", .{});
        return 3;
    }
    if (host.emitted.items.len == 0 or host.emitted.items[0].signature[0] == 0 and allZero(&host.emitted.items[0].signature)) {
        try printStderrFmt(gpa, "wasm-host: BLOCKER — emitted envelope carries empty signature (SEC2 violation)\n", .{});
        return 4;
    }

    try printStdoutFmt(gpa, "wasm-host: AC1+AC4 ok — emit_count={d} signature_first_byte=0x{x:0>2}\n", .{
        host.emit_count,
        host.emitted.items[0].signature[0],
    });

    // ---------------- AC6: 100-iteration p95 perf ----------------
    var samples: [100]u64 = undefined;
    var i: usize = 0;
    while (i < samples.len) : (i += 1) {
        // Fresh host per iteration so emit_count starts at 0; the
        // per-invocation timing isolates module load + invoke + sign.
        var iter_host = imports_mod.Host.init(gpa, keypair_bytes, &.{});
        defer iter_host.deinit();
        iter_host.beginInvocation(action_name, actor_fp, archiform_fp, module_fp);
        const r = try invokeOnce(gpa, &iter_host, wasm_bytes, &bindings);
        if (r.outcome != .ok) {
            try printStderrFmt(gpa, "wasm-host: BLOCKER — iteration {d} outcome={s}\n", .{
                i,
                imports_mod.outcomeName(r.outcome),
            });
            return 5;
        }
        samples[i] = r.duration_ms;
    }
    const p50 = percentile(samples[0..], 0.50);
    const p95 = percentile(samples[0..], 0.95);
    const max = percentile(samples[0..], 1.0);

    try printStdoutFmt(gpa, "wasm-host: AC6 p50={d}ms p95={d}ms max={d}ms budget={d}ms\n", .{ p50, p95, max, ac6_p95_budget_ms });

    if (p95 > ac6_p95_budget_ms) {
        try printStderrFmt(gpa, "wasm-host: BLOCKER — p95={d}ms exceeds AC6 budget {d}ms\n", .{ p95, ac6_p95_budget_ms });
        return 6;
    }

    try printStdoutFmt(gpa, "wasm-host: all sprint-002 ACs (1,4,6,7) green\n", .{});
    return 0;
}

fn allZero(slice: []const u8) bool {
    for (slice) |b| if (b != 0) return false;
    return true;
}

fn printStdoutFmt(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStdout(s);
}

fn printStderrFmt(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStderr(s);
}
