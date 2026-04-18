//! Tiny flag parser — no dependency, just a linear scan for
//! `--name value` / `--name=value` / `--flag`.

const std = @import("std");

pub const ArgError = error{ MissingValue, UnknownFlag };

pub const Spec = struct {
    long: []const u8,
    takes_value: bool = true,
};

pub const Parsed = struct {
    /// Slice into the original argv; valid as long as argv is alive.
    values: []?[]const u8,
    positional: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Parsed) void {
        self.allocator.free(self.values);
        self.positional.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn get(self: Parsed, idx: usize) ?[]const u8 {
        return self.values[idx];
    }

    pub fn flag(self: Parsed, idx: usize) bool {
        return self.values[idx] != null;
    }
};

pub fn parse(allocator: std.mem.Allocator, argv: [][:0]const u8, specs: []const Spec) !Parsed {
    var values = try allocator.alloc(?[]const u8, specs.len);
    @memset(values, null);
    var positional: std.ArrayList([]const u8) = .empty;
    errdefer positional.deinit(allocator);

    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (!std.mem.startsWith(u8, a, "--")) {
            try positional.append(allocator, a);
            continue;
        }
        const after = a[2..];
        const eq_idx = std.mem.indexOfScalar(u8, after, '=');
        const name = if (eq_idx) |j| after[0..j] else after;
        const inline_val: ?[]const u8 = if (eq_idx) |j| after[j + 1 ..] else null;

        var matched: ?usize = null;
        for (specs, 0..) |s, idx| {
            if (std.mem.eql(u8, s.long, name)) {
                matched = idx;
                break;
            }
        }
        const slot = matched orelse return ArgError.UnknownFlag;
        const spec = specs[slot];
        if (!spec.takes_value) {
            values[slot] = ""; // presence marker
            continue;
        }
        if (inline_val) |v| {
            values[slot] = v;
        } else {
            if (i + 1 >= argv.len) return ArgError.MissingValue;
            i += 1;
            values[slot] = argv[i];
        }
    }

    return .{
        .values = values,
        .positional = positional,
        .allocator = allocator,
    };
}

test "parse extracts long values and positionals" {
    const t = std.testing;
    const argv_owned = [_][:0]const u8{ "--out", "/tmp/x.jelly", "--name", "curiosity", "input.bin" };
    const argv = argv_owned[0..];
    const specs = [_]Spec{
        .{ .long = "out" },
        .{ .long = "name" },
        .{ .long = "compress", .takes_value = false },
    };
    var parsed = try parse(t.allocator, @constCast(argv), &specs);
    defer parsed.deinit();
    try t.expectEqualStrings("/tmp/x.jelly", parsed.get(0).?);
    try t.expectEqualStrings("curiosity", parsed.get(1).?);
    try t.expect(!parsed.flag(2));
    try t.expectEqual(@as(usize, 1), parsed.positional.items.len);
    try t.expectEqualStrings("input.bin", parsed.positional.items[0]);
}

test "parse handles --key=value form and presence flags" {
    const t = std.testing;
    const argv_owned = [_][:0]const u8{ "--out=/tmp/y.jelly", "--compress" };
    const argv = argv_owned[0..];
    const specs = [_]Spec{
        .{ .long = "out" },
        .{ .long = "compress", .takes_value = false },
    };
    var parsed = try parse(t.allocator, @constCast(argv), &specs);
    defer parsed.deinit();
    try t.expectEqualStrings("/tmp/y.jelly", parsed.get(0).?);
    try t.expect(parsed.flag(1));
}
