//! Shared file I/O helpers for CLI commands.

const std = @import("std");
const Allocator = std.mem.Allocator;

const io = @import("../io.zig");

pub fn readFile(gpa: Allocator, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io.io(), path, .{});
    defer file.close(io.io());
    const stat = try file.stat(io.io());
    const size: usize = @intCast(stat.size);
    const bytes = try gpa.alloc(u8, size);
    errdefer gpa.free(bytes);
    var buf: [4096]u8 = undefined;
    var r = file.reader(io.io(), &buf);
    try r.interface.readSliceAll(bytes);
    return bytes;
}

pub fn writeFile(path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io.io(), path, .{ .truncate = true });
    defer file.close(io.io());
    var buf: [4096]u8 = undefined;
    var w = file.writer(io.io(), &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}
