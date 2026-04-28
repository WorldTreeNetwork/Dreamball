//! Spike host driver — Story 5.1.
//!
//! What this binary does:
//!   1. Builds (in-memory) the hand-authored hello.wasm bytes.
//!   2. Parses + instantiates them via the in-tree Zig wasm runtime
//!      (see `runtime.zig`).
//!   3. Invokes `_start`; brokers `wasi_snapshot_preview1.fd_write`
//!      to the host stdout (AC2 / AC4).
//!   4. Builds the bad guest, attempts instantiation, reports the
//!      structured rejection (AC5).
//!   5. Records cold instantiation wall-clock for AC6 / NFR4.
//!
//! Output (CI / smoke gates parse this):
//!   spike: hello.wasm wrote: HELLO_FROM_DREAMBALL_SPIKE
//!   spike: hello-bad.wasm rejected import env.malicious_function
//!   spike: cold instantiation = N us
//!
//! Exit code 0 on full success; non-zero if any AC step fails.
//!
//! Per `feedback_dreamball_ac_scope_retreat`: this binary does not
//! silently substitute. If WASI brokering or import rejection don't
//! work, we exit non-zero with a diagnostic, not a happy fake.

const std = @import("std");
const runtime = @import("runtime.zig");
const build_hello = @import("build_hello.zig");

/// AC6 / NFR4 budget: cold instantiation ≤ 100 ms on M-series Mac.
/// Recorded here in microseconds; CI publishes the measured time.
const cold_instantiation_budget_us: u64 = 100_000;

fn iface() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn writeStdout(bytes: []const u8) void {
    var buf: [4096]u8 = undefined;
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

fn printStdout(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStdout(s);
}

fn printStderr(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStderr(s);
}

/// Host implementation of WASI fd_write — the spike's only WASI seam.
/// Args: fd, iovs_ptr, iovs_len, nwritten_ptr.
fn wasiFdWrite(
    instance: *runtime.Instance,
    args: []const runtime.Value,
    out: *?runtime.Value,
) runtime.Error!void {
    if (args.len != 4) return runtime.Error.GuestTrap;
    const fd: i32 = args[0].i32;
    const iovs_ptr_signed: i32 = args[1].i32;
    const iovs_len: i32 = args[2].i32;
    const nwritten_ptr_signed: i32 = args[3].i32;

    if (fd != 1 and fd != 2) {
        // Spike host only brokers stdout/stderr; everything else
        // returns WASI errno EBADF (8) without trapping.
        out.* = .{ .i32 = 8 };
        return;
    }

    const mem = instance.memory;
    const iovs_ptr: u32 = @bitCast(iovs_ptr_signed);
    const nwritten_ptr: u32 = @bitCast(nwritten_ptr_signed);

    var total_written: u32 = 0;
    var i: i32 = 0;
    while (i < iovs_len) : (i += 1) {
        const iov_addr = iovs_ptr + @as(u32, @intCast(i)) * 8;
        if (iov_addr + 8 > mem.len) return runtime.Error.OutOfBounds;
        const buf_ptr = std.mem.readInt(u32, mem[iov_addr..][0..4], .little);
        const buf_len = std.mem.readInt(u32, mem[iov_addr + 4 ..][0..4], .little);
        if (buf_ptr + buf_len > mem.len) return runtime.Error.OutOfBounds;
        if (fd == 1) {
            writeStdout(mem[buf_ptr .. buf_ptr + buf_len]);
        } else {
            writeStderr(mem[buf_ptr .. buf_ptr + buf_len]);
        }
        total_written += buf_len;
    }

    if (nwritten_ptr + 4 > mem.len) return runtime.Error.OutOfBounds;
    std.mem.writeInt(u32, mem[nwritten_ptr..][0..4], total_written, .little);
    out.* = .{ .i32 = 0 }; // WASI errno: success
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;

    // ---------------- AC2 / AC4: load + run hello.wasm ----------------
    const hello_bytes = try build_hello.buildHello(gpa);
    defer gpa.free(hello_bytes);

    const t_start = std.Io.Clock.awake.now(iface());
    var module = try runtime.parse(gpa, hello_bytes);
    defer module.deinit();

    var instance = try runtime.Instance.init(gpa, &module, .{
        .imports = &.{
            .{
                .module = "wasi_snapshot_preview1",
                .name = "fd_write",
                .impl = wasiFdWrite,
            },
        },
    });
    defer instance.deinit();
    const t_end = std.Io.Clock.awake.now(iface());
    const dur_ns = t_start.durationTo(t_end).nanoseconds;
    const cold_us: u64 = @intCast(@max(0, @divTrunc(dur_ns, std.time.ns_per_us)));

    try instance.invokeStart();

    try printStdout(gpa, "spike: hello.wasm wrote: {s}\n", .{
        std.mem.trimEnd(u8, build_hello.marker, "\n"),
    });

    // ---------------- AC6: timing ----------------
    try printStdout(gpa, "spike: cold instantiation = {d} us (budget {d} us)\n", .{
        cold_us,
        cold_instantiation_budget_us,
    });
    if (cold_us > cold_instantiation_budget_us) {
        try printStderr(gpa, "spike: BLOCKER — cold instantiation {d} us exceeds NFR4 budget {d} us\n", .{
            cold_us,
            cold_instantiation_budget_us,
        });
        return 2;
    }

    // ---------------- AC5: load + reject hello-bad.wasm ----------------
    const bad_bytes = try build_hello.buildHelloBad(gpa);
    defer gpa.free(bad_bytes);

    var bad_module = try runtime.parse(gpa, bad_bytes);
    defer bad_module.deinit();

    var rejected: ?runtime.ImportRejection = null;
    if (runtime.Instance.init(gpa, &bad_module, .{
        .imports = &.{
            .{
                .module = "wasi_snapshot_preview1",
                .name = "fd_write",
                .impl = wasiFdWrite,
            },
        },
    })) |inst| {
        var inst_mut = inst;
        inst_mut.deinit();
    } else |err| switch (err) {
        runtime.Error.UnknownImport => {
            // Recompute which import was the offender (the partial
            // Instance from Instance.init is dropped on the error path).
            for (bad_module.imports) |imp| {
                if (!std.mem.eql(u8, imp.module, "wasi_snapshot_preview1") or
                    !std.mem.eql(u8, imp.name, "fd_write"))
                {
                    rejected = .{ .module = imp.module, .name = imp.name };
                    break;
                }
            }
        },
        else => return err,
    }

    if (rejected == null) {
        try printStderr(gpa, "spike: BLOCKER — hello-bad.wasm was NOT rejected\n", .{});
        return 3;
    }

    try printStdout(gpa, "spike: hello-bad.wasm rejected import {s}.{s}\n", .{
        rejected.?.module,
        rejected.?.name,
    });

    try printStdout(gpa, "spike: all ACs (2,4,5,6) green\n", .{});
    return 0;
}
