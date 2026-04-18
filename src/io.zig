//! Thin helpers around Zig 0.16's `std.Io` interface — lets the rest of the
//! code write to stdout/stderr without threading an `Io` value through every
//! call site.

const std = @import("std");

pub fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

pub fn printStdout(comptime fmt: []const u8, args: anytype) !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const s = try std.fmt.allocPrint(gpa, fmt, args);
    defer gpa.free(s);
    try writeAllStdout(s);
}

pub fn writeAllStdout(bytes: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stdout().writer(io(), &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

pub fn writeAllStderr(bytes: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stderr().writer(io(), &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

/// Unix epoch seconds via `std.Io.Clock.real.now`.
pub fn unixSeconds() i64 {
    const ts = std.Io.Clock.real.now(io());
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}
