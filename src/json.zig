//! Lossless JSON export for a DreamBall, matching PROTOCOL.md §7.
//!
//! Byte strings are rendered as `"b58:<base58>"` strings so consumers without
//! CBOR tooling can still read `.jelly.json`. Import-from-JSON lives next
//! sprint; for now we only export.

const std = @import("std");
const Allocator = std.mem.Allocator;

const protocol = @import("protocol.zig");
const base58 = @import("base58.zig");

/// Small string-builder that wraps the 0.16 unmanaged `std.ArrayList(u8)` API.
const Buf = struct {
    allocator: Allocator,
    inner: std.ArrayList(u8),

    fn init(allocator: Allocator) Buf {
        return .{ .allocator = allocator, .inner = .empty };
    }

    fn deinit(self: *Buf) void {
        self.inner.deinit(self.allocator);
    }

    fn toOwned(self: *Buf) ![]u8 {
        return self.inner.toOwnedSlice(self.allocator);
    }

    fn writeByte(self: *Buf, b: u8) !void {
        try self.inner.append(self.allocator, b);
    }

    fn writeAll(self: *Buf, s: []const u8) !void {
        try self.inner.appendSlice(self.allocator, s);
    }

    fn print(self: *Buf, comptime fmt: []const u8, args: anytype) !void {
        const written = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(written);
        try self.inner.appendSlice(self.allocator, written);
    }
};

pub fn writeDreamBall(allocator: Allocator, db: protocol.DreamBall) ![]u8 {
    var buf = Buf.init(allocator);
    errdefer buf.deinit();

    try buf.writeByte('{');

    try writeKey(&buf, "type");
    try buf.writeByte('"');
    if (db.dreamball_type) |t| {
        try buf.writeAll(t.toWireString());
    } else {
        try buf.writeAll("jelly.dreamball");
    }
    try buf.writeByte('"');
    try buf.writeByte(',');

    try writeKey(&buf, "format-version");
    try buf.print("{d}", .{protocol.FORMAT_VERSION});
    try buf.writeByte(',');

    try writeKey(&buf, "stage");
    try buf.writeByte('"');
    try buf.writeAll(db.stage.toString());
    try buf.writeByte('"');
    try buf.writeByte(',');

    try writeKey(&buf, "identity");
    try writeB58(allocator, &buf, &db.identity);
    try buf.writeByte(',');

    try writeKey(&buf, "genesis-hash");
    try writeB58(allocator, &buf, &db.genesis_hash);
    try buf.writeByte(',');

    try writeKey(&buf, "revision");
    try buf.print("{d}", .{db.revision});

    if (db.name) |n| {
        try buf.writeByte(',');
        try writeKey(&buf, "name");
        try writeEscapedString(&buf, n);
    }

    if (db.created) |t| {
        try buf.writeByte(',');
        try writeKey(&buf, "created");
        try writeRfc3339(&buf, t);
    }

    if (db.updated) |t| {
        try buf.writeByte(',');
        try writeKey(&buf, "updated");
        try writeRfc3339(&buf, t);
    }

    if (db.note) |n| {
        try buf.writeByte(',');
        try writeKey(&buf, "note");
        try writeEscapedString(&buf, n);
    }

    if (db.look) |l| {
        try buf.writeByte(',');
        try writeKey(&buf, "look");
        try writeLook(allocator, &buf, l);
    }

    if (db.feel) |f| {
        try buf.writeByte(',');
        try writeKey(&buf, "feel");
        try writeFeel(&buf, f);
    }

    if (db.act) |a| {
        try buf.writeByte(',');
        try writeKey(&buf, "act");
        try writeAct(allocator, &buf, a);
    }

    if (db.guilds.len > 0) {
        try buf.writeByte(',');
        try writeKey(&buf, "guild");
        try buf.writeByte('[');
        for (db.guilds, 0..) |fp, i| {
            if (i > 0) try buf.writeByte(',');
            try writeB58(allocator, &buf, &fp.bytes);
        }
        try buf.writeByte(']');
    }

    if (db.contains.len > 0) {
        try buf.writeByte(',');
        try writeKey(&buf, "contains");
        try buf.writeByte('[');
        for (db.contains, 0..) |fp, i| {
            if (i > 0) try buf.writeByte(',');
            try writeB58(allocator, &buf, &fp.bytes);
        }
        try buf.writeByte(']');
    }

    if (db.derived_from.len > 0) {
        try buf.writeByte(',');
        try writeKey(&buf, "derived-from");
        try buf.writeByte('[');
        for (db.derived_from, 0..) |fp, i| {
            if (i > 0) try buf.writeByte(',');
            try writeB58(allocator, &buf, &fp.bytes);
        }
        try buf.writeByte(']');
    }

    if (db.signatures.len > 0) {
        try buf.writeByte(',');
        try writeKey(&buf, "signatures");
        try buf.writeByte('[');
        for (db.signatures, 0..) |sig, i| {
            if (i > 0) try buf.writeByte(',');
            try buf.writeByte('{');
            try writeKey(&buf, "alg");
            try writeEscapedString(&buf, sig.alg);
            try buf.writeByte(',');
            try writeKey(&buf, "value");
            try writeB58(allocator, &buf, sig.value);
            try buf.writeByte('}');
        }
        try buf.writeByte(']');
    }

    try buf.writeByte('}');
    return buf.toOwned();
}

fn writeKey(buf: *Buf, key: []const u8) !void {
    try buf.writeByte('"');
    try buf.writeAll(key);
    try buf.writeByte('"');
    try buf.writeByte(':');
}

fn writeB58(allocator: Allocator, buf: *Buf, bytes: []const u8) !void {
    const enc = try base58.encode(allocator, bytes);
    defer allocator.free(enc);
    try buf.writeByte('"');
    try buf.writeAll("b58:");
    try buf.writeAll(enc);
    try buf.writeByte('"');
}

fn writeEscapedString(buf: *Buf, s: []const u8) !void {
    try buf.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.writeAll("\\\""),
            '\\' => try buf.writeAll("\\\\"),
            '\n' => try buf.writeAll("\\n"),
            '\r' => try buf.writeAll("\\r"),
            '\t' => try buf.writeAll("\\t"),
            0...0x08, 0x0B, 0x0C, 0x0E...0x1F => try buf.print("\\u{x:0>4}", .{c}),
            else => try buf.writeByte(c),
        }
    }
    try buf.writeByte('"');
}

fn writeAsset(allocator: Allocator, buf: *Buf, a: protocol.Asset) !void {
    try buf.writeByte('{');
    try writeKey(buf, "type");
    try buf.writeAll("\"jelly.asset\"");
    try buf.writeByte(',');
    try writeKey(buf, "format-version");
    try buf.print("{d}", .{protocol.FORMAT_VERSION});
    try buf.writeByte(',');
    try writeKey(buf, "media-type");
    try writeEscapedString(buf, a.media_type);
    try buf.writeByte(',');
    try writeKey(buf, "hash");
    try writeB58(allocator, buf, &a.hash);
    if (a.urls.len > 0) {
        try buf.writeByte(',');
        try writeKey(buf, "url");
        try buf.writeByte('[');
        for (a.urls, 0..) |u, i| {
            if (i > 0) try buf.writeByte(',');
            try writeEscapedString(buf, u);
        }
        try buf.writeByte(']');
    }
    if (a.embedded) |e| {
        try buf.writeByte(',');
        try writeKey(buf, "embedded");
        try writeB58(allocator, buf, e);
    }
    if (a.size) |s| {
        try buf.writeByte(',');
        try writeKey(buf, "size");
        try buf.print("{d}", .{s});
    }
    if (a.note) |n| {
        try buf.writeByte(',');
        try writeKey(buf, "note");
        try writeEscapedString(buf, n);
    }
    try buf.writeByte('}');
}

fn writeSkill(allocator: Allocator, buf: *Buf, s: protocol.Skill) !void {
    try buf.writeByte('{');
    try writeKey(buf, "type");
    try buf.writeAll("\"jelly.skill\"");
    try buf.writeByte(',');
    try writeKey(buf, "format-version");
    try buf.print("{d}", .{protocol.FORMAT_VERSION});
    try buf.writeByte(',');
    try writeKey(buf, "name");
    try writeEscapedString(buf, s.name);
    if (s.trigger) |t| {
        try buf.writeByte(',');
        try writeKey(buf, "trigger");
        try writeEscapedString(buf, t);
    }
    if (s.body) |b| {
        try buf.writeByte(',');
        try writeKey(buf, "body");
        try writeEscapedString(buf, b);
    }
    if (s.asset) |a| {
        try buf.writeByte(',');
        try writeKey(buf, "asset");
        try writeAsset(allocator, buf, a);
    }
    if (s.requires.len > 0) {
        try buf.writeByte(',');
        try writeKey(buf, "requires");
        try buf.writeByte('[');
        for (s.requires, 0..) |r, i| {
            if (i > 0) try buf.writeByte(',');
            try writeEscapedString(buf, r);
        }
        try buf.writeByte(']');
    }
    if (s.note) |n| {
        try buf.writeByte(',');
        try writeKey(buf, "note");
        try writeEscapedString(buf, n);
    }
    try buf.writeByte('}');
}

fn writeLook(allocator: Allocator, buf: *Buf, l: protocol.Look) !void {
    try buf.writeByte('{');
    try writeKey(buf, "type");
    try buf.writeAll("\"jelly.look\"");
    try buf.writeByte(',');
    try writeKey(buf, "format-version");
    try buf.print("{d}", .{protocol.FORMAT_VERSION});
    if (l.assets.len > 0) {
        try buf.writeByte(',');
        try writeKey(buf, "asset");
        try buf.writeByte('[');
        for (l.assets, 0..) |a, i| {
            if (i > 0) try buf.writeByte(',');
            try writeAsset(allocator, buf, a);
        }
        try buf.writeByte(']');
    }
    if (l.preview) |p| {
        try buf.writeByte(',');
        try writeKey(buf, "preview");
        try writeAsset(allocator, buf, p);
    }
    if (l.background) |bg| {
        try buf.writeByte(',');
        try writeKey(buf, "background");
        try writeEscapedString(buf, bg);
    }
    if (l.note) |n| {
        try buf.writeByte(',');
        try writeKey(buf, "note");
        try writeEscapedString(buf, n);
    }
    try buf.writeByte('}');
}

fn writeFeel(buf: *Buf, f: protocol.Feel) !void {
    try buf.writeByte('{');
    try writeKey(buf, "type");
    try buf.writeAll("\"jelly.feel\"");
    try buf.writeByte(',');
    try writeKey(buf, "format-version");
    try buf.print("{d}", .{protocol.FORMAT_VERSION});
    if (f.personality) |p| {
        try buf.writeByte(',');
        try writeKey(buf, "personality");
        try writeEscapedString(buf, p);
    }
    if (f.voice) |v| {
        try buf.writeByte(',');
        try writeKey(buf, "voice");
        try writeEscapedString(buf, v);
    }
    if (f.values.len > 0) {
        try buf.writeByte(',');
        try writeKey(buf, "values");
        try buf.writeByte('[');
        for (f.values, 0..) |v, i| {
            if (i > 0) try buf.writeByte(',');
            try writeEscapedString(buf, v);
        }
        try buf.writeByte(']');
    }
    if (f.tempo) |t| {
        try buf.writeByte(',');
        try writeKey(buf, "tempo");
        try writeEscapedString(buf, t);
    }
    if (f.note) |n| {
        try buf.writeByte(',');
        try writeKey(buf, "note");
        try writeEscapedString(buf, n);
    }
    try buf.writeByte('}');
}

fn writeAct(allocator: Allocator, buf: *Buf, a: protocol.Act) !void {
    try buf.writeByte('{');
    try writeKey(buf, "type");
    try buf.writeAll("\"jelly.act\"");
    try buf.writeByte(',');
    try writeKey(buf, "format-version");
    try buf.print("{d}", .{protocol.FORMAT_VERSION});
    if (a.model) |m| {
        try buf.writeByte(',');
        try writeKey(buf, "model");
        try writeEscapedString(buf, m);
    }
    if (a.system_prompt) |sp| {
        try buf.writeByte(',');
        try writeKey(buf, "system-prompt");
        try writeEscapedString(buf, sp);
    }
    if (a.skills.len > 0) {
        try buf.writeByte(',');
        try writeKey(buf, "skill");
        try buf.writeByte('[');
        for (a.skills, 0..) |s, i| {
            if (i > 0) try buf.writeByte(',');
            try writeSkill(allocator, buf, s);
        }
        try buf.writeByte(']');
    }
    if (a.scripts.len > 0) {
        try buf.writeByte(',');
        try writeKey(buf, "script");
        try buf.writeByte('[');
        for (a.scripts, 0..) |sc, i| {
            if (i > 0) try buf.writeByte(',');
            try writeAsset(allocator, buf, sc);
        }
        try buf.writeByte(']');
    }
    if (a.tools.len > 0) {
        try buf.writeByte(',');
        try writeKey(buf, "tool");
        try buf.writeByte('[');
        for (a.tools, 0..) |t, i| {
            if (i > 0) try buf.writeByte(',');
            try writeEscapedString(buf, t);
        }
        try buf.writeByte(']');
    }
    if (a.note) |n| {
        try buf.writeByte(',');
        try writeKey(buf, "note");
        try writeEscapedString(buf, n);
    }
    try buf.writeByte('}');
}

// ============================================================================
// Import path — read a canonical .jelly.json back into a DreamBall struct.
//
// Lifetimes: `readDreamBall` uses the provided allocator (typically an arena)
// for every string/slice inside the returned DreamBall, so the caller can
// free everything in one shot by resetting the arena after use.
// ============================================================================

const Fingerprint = @import("fingerprint.zig").Fingerprint;

pub const ImportError = error{
    InvalidJson,
    InvalidBase58Prefix,
    WrongType,
    MissingField,
    TooManyValues,
    OutOfMemory,
    InvalidBase58Char,
};

pub fn readDreamBall(arena: Allocator, json_text: []const u8) ImportError!protocol.DreamBall {
    const parsed = std.json.parseFromSliceLeaky(
        std.json.Value,
        arena,
        json_text,
        .{},
    ) catch return ImportError.InvalidJson;

    return dreamBallFromValue(arena, parsed);
}

fn dreamBallFromValue(arena: Allocator, v: std.json.Value) ImportError!protocol.DreamBall {
    const obj = switch (v) {
        .object => |o| o,
        else => return ImportError.InvalidJson,
    };

    try expectStringEq(obj, "type", "jelly.dreamball");

    const identity = try decodeB58Field(arena, obj, "identity");
    if (identity.len != 32) return ImportError.InvalidJson;
    const genesis = try decodeB58Field(arena, obj, "genesis-hash");
    if (genesis.len != 32) return ImportError.InvalidJson;

    var db = protocol.DreamBall{
        .stage = blk: {
            const s = obj.get("stage") orelse return ImportError.MissingField;
            const txt = switch (s) {
                .string => |t| t,
                else => return ImportError.InvalidJson,
            };
            break :blk protocol.Stage.fromString(txt) orelse return ImportError.InvalidJson;
        },
        .identity = undefined,
        .genesis_hash = undefined,
        .revision = blk: {
            const r = obj.get("revision") orelse return ImportError.MissingField;
            break :blk switch (r) {
                .integer => |i| @as(u32, @intCast(i)),
                else => return ImportError.InvalidJson,
            };
        },
    };
    @memcpy(&db.identity, identity);
    @memcpy(&db.genesis_hash, genesis);

    if (obj.get("name")) |n| db.name = try getString(n);
    if (obj.get("note")) |n| db.note = try getString(n);
    if (obj.get("created")) |c| db.created = try parseRfc3339(try getString(c));
    if (obj.get("updated")) |u| db.updated = try parseRfc3339(try getString(u));

    if (obj.get("look")) |l| db.look = try lookFromValue(arena, l);
    if (obj.get("feel")) |f| db.feel = try feelFromValue(arena, f);
    if (obj.get("act")) |a| db.act = try actFromValue(arena, a);

    if (obj.get("contains")) |c| {
        const arr = switch (c) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const fps = try arena.alloc(Fingerprint, arr.items.len);
        for (arr.items, 0..) |item, i| {
            const dec = try decodeB58Value(arena, item);
            if (dec.len != 32) return ImportError.InvalidJson;
            @memcpy(&fps[i].bytes, dec);
        }
        db.contains = fps;
    }
    if (obj.get("derived-from")) |d| {
        const arr = switch (d) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const fps = try arena.alloc(Fingerprint, arr.items.len);
        for (arr.items, 0..) |item, i| {
            const dec = try decodeB58Value(arena, item);
            if (dec.len != 32) return ImportError.InvalidJson;
            @memcpy(&fps[i].bytes, dec);
        }
        db.derived_from = fps;
    }
    if (obj.get("signatures")) |s| {
        const arr = switch (s) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const sigs = try arena.alloc(protocol.Signature, arr.items.len);
        for (arr.items, 0..) |item, i| {
            const sobj = switch (item) {
                .object => |o| o,
                else => return ImportError.InvalidJson,
            };
            const alg_v = sobj.get("alg") orelse return ImportError.MissingField;
            const val_v = sobj.get("value") orelse return ImportError.MissingField;
            sigs[i] = .{
                .alg = try dupeString(arena, try getString(alg_v)),
                .value = try decodeB58Value(arena, val_v),
            };
        }
        db.signatures = sigs;
    }

    return db;
}

fn expectStringEq(obj: std.json.ObjectMap, key: []const u8, want: []const u8) ImportError!void {
    const v = obj.get(key) orelse return ImportError.MissingField;
    const t = switch (v) {
        .string => |s| s,
        else => return ImportError.WrongType,
    };
    if (!std.mem.eql(u8, t, want)) return ImportError.WrongType;
}

fn getString(v: std.json.Value) ImportError![]const u8 {
    return switch (v) {
        .string => |s| s,
        else => ImportError.WrongType,
    };
}

fn decodeB58Field(arena: Allocator, obj: std.json.ObjectMap, key: []const u8) ImportError![]const u8 {
    const v = obj.get(key) orelse return ImportError.MissingField;
    return decodeB58Value(arena, v);
}

fn decodeB58Value(arena: Allocator, v: std.json.Value) ImportError![]const u8 {
    const s = try getString(v);
    if (!std.mem.startsWith(u8, s, "b58:")) return ImportError.InvalidBase58Prefix;
    return base58.decode(arena, s[4..]) catch |err| switch (err) {
        error.InvalidBase58Char => return ImportError.InvalidBase58Char,
        error.OutOfMemory => return ImportError.OutOfMemory,
    };
}

fn dupeString(arena: Allocator, s: []const u8) ImportError![]const u8 {
    return arena.dupe(u8, s) catch ImportError.OutOfMemory;
}

fn assetFromValue(arena: Allocator, v: std.json.Value) ImportError!protocol.Asset {
    const obj = switch (v) {
        .object => |o| o,
        else => return ImportError.InvalidJson,
    };
    try expectStringEq(obj, "type", "jelly.asset");
    const mt_v = obj.get("media-type") orelse return ImportError.MissingField;
    const hash_bytes = try decodeB58Field(arena, obj, "hash");
    if (hash_bytes.len != 32) return ImportError.InvalidJson;

    var asset = protocol.Asset{
        .media_type = try dupeString(arena, try getString(mt_v)),
        .hash = undefined,
    };
    @memcpy(&asset.hash, hash_bytes);

    if (obj.get("url")) |urls_v| {
        const arr = switch (urls_v) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const urls = try arena.alloc([]const u8, arr.items.len);
        for (arr.items, 0..) |item, i| urls[i] = try dupeString(arena, try getString(item));
        asset.urls = urls;
    }
    if (obj.get("embedded")) |e| asset.embedded = try decodeB58Value(arena, e);
    if (obj.get("size")) |s| asset.size = switch (s) {
        .integer => |i| @as(u64, @intCast(i)),
        else => return ImportError.InvalidJson,
    };
    if (obj.get("note")) |n| asset.note = try dupeString(arena, try getString(n));
    return asset;
}

fn skillFromValue(arena: Allocator, v: std.json.Value) ImportError!protocol.Skill {
    const obj = switch (v) {
        .object => |o| o,
        else => return ImportError.InvalidJson,
    };
    try expectStringEq(obj, "type", "jelly.skill");
    const name_v = obj.get("name") orelse return ImportError.MissingField;
    var skill = protocol.Skill{ .name = try dupeString(arena, try getString(name_v)) };
    if (obj.get("trigger")) |t| skill.trigger = try dupeString(arena, try getString(t));
    if (obj.get("body")) |b| skill.body = try dupeString(arena, try getString(b));
    if (obj.get("asset")) |a| skill.asset = try assetFromValue(arena, a);
    if (obj.get("requires")) |r| {
        const arr = switch (r) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const reqs = try arena.alloc([]const u8, arr.items.len);
        for (arr.items, 0..) |item, i| reqs[i] = try dupeString(arena, try getString(item));
        skill.requires = reqs;
    }
    if (obj.get("note")) |n| skill.note = try dupeString(arena, try getString(n));
    return skill;
}

fn lookFromValue(arena: Allocator, v: std.json.Value) ImportError!protocol.Look {
    const obj = switch (v) {
        .object => |o| o,
        else => return ImportError.InvalidJson,
    };
    try expectStringEq(obj, "type", "jelly.look");
    var look = protocol.Look{};
    if (obj.get("asset")) |a| {
        const arr = switch (a) {
            .array => |x| x,
            else => return ImportError.InvalidJson,
        };
        const assets = try arena.alloc(protocol.Asset, arr.items.len);
        for (arr.items, 0..) |item, i| assets[i] = try assetFromValue(arena, item);
        look.assets = assets;
    }
    if (obj.get("preview")) |p| look.preview = try assetFromValue(arena, p);
    if (obj.get("background")) |bg| look.background = try dupeString(arena, try getString(bg));
    if (obj.get("note")) |n| look.note = try dupeString(arena, try getString(n));
    return look;
}

fn feelFromValue(arena: Allocator, v: std.json.Value) ImportError!protocol.Feel {
    const obj = switch (v) {
        .object => |o| o,
        else => return ImportError.InvalidJson,
    };
    try expectStringEq(obj, "type", "jelly.feel");
    var feel = protocol.Feel{};
    if (obj.get("personality")) |p| feel.personality = try dupeString(arena, try getString(p));
    if (obj.get("voice")) |x| feel.voice = try dupeString(arena, try getString(x));
    if (obj.get("values")) |vals_v| {
        const arr = switch (vals_v) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const vals = try arena.alloc([]const u8, arr.items.len);
        for (arr.items, 0..) |item, i| vals[i] = try dupeString(arena, try getString(item));
        feel.values = vals;
    }
    if (obj.get("tempo")) |t| feel.tempo = try dupeString(arena, try getString(t));
    if (obj.get("note")) |n| feel.note = try dupeString(arena, try getString(n));
    return feel;
}

fn actFromValue(arena: Allocator, v: std.json.Value) ImportError!protocol.Act {
    const obj = switch (v) {
        .object => |o| o,
        else => return ImportError.InvalidJson,
    };
    try expectStringEq(obj, "type", "jelly.act");
    var act = protocol.Act{};
    if (obj.get("model")) |m| act.model = try dupeString(arena, try getString(m));
    if (obj.get("system-prompt")) |sp| act.system_prompt = try dupeString(arena, try getString(sp));
    if (obj.get("skill")) |sk| {
        const arr = switch (sk) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const skills = try arena.alloc(protocol.Skill, arr.items.len);
        for (arr.items, 0..) |item, i| skills[i] = try skillFromValue(arena, item);
        act.skills = skills;
    }
    if (obj.get("script")) |sc| {
        const arr = switch (sc) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const scripts = try arena.alloc(protocol.Asset, arr.items.len);
        for (arr.items, 0..) |item, i| scripts[i] = try assetFromValue(arena, item);
        act.scripts = scripts;
    }
    if (obj.get("tool")) |tl| {
        const arr = switch (tl) {
            .array => |a| a,
            else => return ImportError.InvalidJson,
        };
        const tools = try arena.alloc([]const u8, arr.items.len);
        for (arr.items, 0..) |item, i| tools[i] = try dupeString(arena, try getString(item));
        act.tools = tools;
    }
    if (obj.get("note")) |n| act.note = try dupeString(arena, try getString(n));
    return act;
}

/// Parse RFC 3339 "YYYY-MM-DDTHH:MM:SSZ" → Unix epoch seconds (UTC only).
fn parseRfc3339(s: []const u8) ImportError!i64 {
    if (s.len != 20) return ImportError.InvalidJson;
    if (s[4] != '-' or s[7] != '-' or s[10] != 'T' or s[13] != ':' or s[16] != ':' or s[19] != 'Z') {
        return ImportError.InvalidJson;
    }
    const year = std.fmt.parseInt(u16, s[0..4], 10) catch return ImportError.InvalidJson;
    const month = std.fmt.parseInt(u8, s[5..7], 10) catch return ImportError.InvalidJson;
    const day = std.fmt.parseInt(u8, s[8..10], 10) catch return ImportError.InvalidJson;
    const hour = std.fmt.parseInt(u8, s[11..13], 10) catch return ImportError.InvalidJson;
    const minute = std.fmt.parseInt(u8, s[14..16], 10) catch return ImportError.InvalidJson;
    const second = std.fmt.parseInt(u8, s[17..19], 10) catch return ImportError.InvalidJson;

    // Days from 1970-01-01 to YYYY-MM-DD.
    var days_total: i64 = 0;
    var y: u16 = 1970;
    while (y < year) : (y += 1) days_total += if (isLeap(y)) @as(i64, 366) else 365;
    const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var m: u8 = 1;
    while (m < month) : (m += 1) {
        var d: i64 = @as(i64, month_days[m - 1]);
        if (m == 2 and isLeap(year)) d += 1;
        days_total += d;
    }
    days_total += @as(i64, day - 1);

    const seconds = days_total * 86400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
    return seconds;
}

fn isLeap(y: u16) bool {
    return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0;
}

fn writeRfc3339(buf: *Buf, epoch: i64) !void {
    const secs = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch) };
    const day = secs.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const t = secs.getDaySeconds();
    try buf.print(
        "\"{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z\"",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            t.getHoursIntoDay(),
            t.getMinutesIntoHour(),
            t.getSecondsIntoMinute(),
        },
    );
}

test "JSON export minimal seed" {
    const allocator = std.testing.allocator;
    const db = protocol.DreamBall{
        .stage = .seed,
        .identity = [_]u8{0xAB} ** 32,
        .genesis_hash = [_]u8{0xCD} ** 32,
        .revision = 0,
    };
    const json = try writeDreamBall(allocator, db);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"jelly.dreamball\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stage\":\"seed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"format-version\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"identity\":\"b58:") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"genesis-hash\":\"b58:") != null);
}

test "JSON export with nested look/feel/act" {
    const allocator = std.testing.allocator;
    const urls = [_][]const u8{"https://example/a.glb"};
    const assets = [_]protocol.Asset{.{
        .media_type = "model/gltf-binary",
        .hash = [_]u8{0xAA} ** 32,
        .urls = &urls,
    }};
    const look = protocol.Look{ .assets = &assets, .background = "color:#123" };
    const values = [_][]const u8{ "curiosity", "clarity" };
    const feel = protocol.Feel{
        .personality = "playful",
        .voice = "quick",
        .values = &values,
    };
    const tools = [_][]const u8{"web.search"};
    const act = protocol.Act{
        .model = "claude-opus-4-7",
        .system_prompt = "You are curiosity.",
        .tools = &tools,
    };
    const db = protocol.DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 3,
        .look = look,
        .feel = feel,
        .act = act,
    };
    const json = try writeDreamBall(allocator, db);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"look\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"jelly.look\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"background\":\"color:#123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"feel\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"personality\":\"playful\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"values\":[\"curiosity\",\"clarity\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"act\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"model\":\"claude-opus-4-7\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tool\":[\"web.search\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"media-type\":\"model/gltf-binary\"") != null);
}

test "JSON round-trip — export → import → encode byte-equal" {
    const allocator = std.testing.allocator;

    const values = [_][]const u8{ "curiosity", "clarity" };
    const feel = protocol.Feel{ .personality = "playful", .values = &values };
    const db_in = protocol.DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{0x42} ** 32,
        .genesis_hash = [_]u8{0x24} ** 32,
        .revision = 3,
        .name = "round-trip test",
        .created = 1712534400,
        .feel = feel,
    };

    const envelope = @import("envelope.zig");
    const cbor_in = try envelope.encodeDreamBall(allocator, db_in);
    defer allocator.free(cbor_in);
    const json_text = try writeDreamBall(allocator, db_in);
    defer allocator.free(json_text);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const db_out = try readDreamBall(arena.allocator(), json_text);

    const cbor_out = try envelope.encodeDreamBall(allocator, db_out);
    defer allocator.free(cbor_out);

    try std.testing.expectEqualSlices(u8, cbor_in, cbor_out);
}

test "parseRfc3339 decodes known epoch" {
    const t = std.testing;
    // 2024-04-08T00:00:00Z = 1712534400
    try t.expectEqual(@as(i64, 1712534400), try parseRfc3339("2024-04-08T00:00:00Z"));
    // 1970-01-01T00:00:00Z = 0
    try t.expectEqual(@as(i64, 0), try parseRfc3339("1970-01-01T00:00:00Z"));
    // 2000-02-29T12:34:56Z — leap day
    try t.expectEqual(@as(i64, 951827696), try parseRfc3339("2000-02-29T12:34:56Z"));
}

test "JSON export populated" {
    const allocator = std.testing.allocator;
    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &[_]u8{ 0x01, 0x02, 0x03 } },
    };
    const db = protocol.DreamBall{
        .stage = .dreamball,
        .identity = [_]u8{1} ** 32,
        .genesis_hash = [_]u8{2} ** 32,
        .revision = 5,
        .name = "Aspect of Curiosity",
        .created = 1712534400,
        .signatures = &sigs,
    };
    const json = try writeDreamBall(allocator, db);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"Aspect of Curiosity\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"revision\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"created\":\"2024-04-08T00:00:00Z\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"alg\":\"ed25519\"") != null);
}
