//! `jelly show --as-palace <palace>` — pretty-print palace topology.
//! `jelly palace show --archiforms` — list the 19 seed forms.
//!
//! AC1: Human-readable output: mythos head body, true-name, room tree with item counts,
//!      timeline head hashes, oracle fp. Golden fixture byte-for-byte match.
//! AC2: `--json` flag: JSON object with keys mythosHeadBody, trueName, rooms[],
//!      timelineHeadHashes[], oracleFp.
//! AC3: Non-palace fp → exit non-zero; stderr "not a palace".
//! AC4: `jelly palace show --archiforms` lists the 19 seed forms.
//! AC12: ≥5 inline test blocks.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");
const palace_mint = @import("palace_mint.zig");

// ── CLI spec for `jelly show --as-palace` path ─────────────────────────────────

const SPECS = [_]args_mod.Spec{
    .{ .long = "json", .takes_value = false },       // 0
    .{ .long = "archiforms", .takes_value = false },  // 1
    .{ .long = "help", .takes_value = false },        // 2
};

// ── Archiform list (19 seed forms; D-014) ─────────────────────────────────────

pub const ARCHIFORMS = [_][]const u8{
    "library", "forge", "throne-room", "garden", "courtyard",
    "lab", "crypt", "portal", "atrium", "cell",
    "scroll", "lantern", "vessel", "compass", "seed",
    "muse", "judge", "midwife", "trickster",
};

// ── CBOR minimal scanner (shared with palace_verify.zig by copy-of-concept) ───
// We only need to extract specific fields from bundle envelopes. Rather than
// pulling the full zbor stack, we use lightweight field extraction.
// These are safe because all bytes come from our own CAS (canonical dCBOR).

const CBOR_MAJOR_BSTR: u8 = 0x40;
const CBOR_MAJOR_TSTR: u8 = 0x60;
const CBOR_MAJOR_ARR: u8 = 0x80;
const CBOR_MAJOR_MAP: u8 = 0xa0;
const CBOR_MAJOR_TAG: u8 = 0xc0;
const CBOR_SIMPLE_TRUE: u8 = 0xf5;
const CBOR_SIMPLE_NULL: u8 = 0xf6;

const ScanError = error{ EndOfBuffer, InvalidCbor };

fn skipCborItem(buf: []const u8, pos: usize) ScanError!usize {
    if (pos >= buf.len) return error.EndOfBuffer;
    const ib = buf[pos];
    const major = ib & 0xe0;
    const info = ib & 0x1f;
    var arg: u64 = 0;
    var header_len: usize = 1;
    switch (info) {
        0...23 => { arg = info; },
        24 => {
            if (pos + 1 >= buf.len) return error.EndOfBuffer;
            arg = buf[pos + 1];
            header_len = 2;
        },
        25 => {
            if (pos + 2 >= buf.len) return error.EndOfBuffer;
            arg = @as(u64, buf[pos + 1]) << 8 | buf[pos + 2];
            header_len = 3;
        },
        26 => {
            if (pos + 4 >= buf.len) return error.EndOfBuffer;
            arg = @as(u64, buf[pos + 1]) << 24 |
                  @as(u64, buf[pos + 2]) << 16 |
                  @as(u64, buf[pos + 3]) << 8 |
                  buf[pos + 4];
            header_len = 5;
        },
        27 => {
            if (pos + 8 >= buf.len) return error.EndOfBuffer;
            arg = @as(u64, buf[pos + 1]) << 56 |
                  @as(u64, buf[pos + 2]) << 48 |
                  @as(u64, buf[pos + 3]) << 40 |
                  @as(u64, buf[pos + 4]) << 32 |
                  @as(u64, buf[pos + 5]) << 24 |
                  @as(u64, buf[pos + 6]) << 16 |
                  @as(u64, buf[pos + 7]) << 8 |
                  buf[pos + 8];
            header_len = 9;
        },
        else => return error.InvalidCbor,
    }
    switch (major) {
        0x00, 0x20 => return header_len,
        CBOR_MAJOR_BSTR, CBOR_MAJOR_TSTR => {
            const total = header_len + @as(usize, @intCast(arg));
            if (pos + total > buf.len) return error.EndOfBuffer;
            return total;
        },
        CBOR_MAJOR_ARR => {
            var off = pos + header_len;
            for (0..@as(usize, @intCast(arg))) |_| {
                off += try skipCborItem(buf, off);
            }
            return off - pos;
        },
        CBOR_MAJOR_MAP => {
            var off = pos + header_len;
            for (0..@as(usize, @intCast(arg))) |_| {
                off += try skipCborItem(buf, off);
                off += try skipCborItem(buf, off);
            }
            return off - pos;
        },
        CBOR_MAJOR_TAG => {
            return header_len + try skipCborItem(buf, pos + header_len);
        },
        0xe0 => return header_len,
        else => return error.InvalidCbor,
    }
}

fn readTstr(buf: []const u8, pos: usize) ScanError!struct { key: []const u8, len: usize } {
    if (pos >= buf.len) return error.EndOfBuffer;
    const ib = buf[pos];
    if ((ib & 0xe0) != CBOR_MAJOR_TSTR) return error.InvalidCbor;
    const info = ib & 0x1f;
    var slen: u64 = 0;
    var hlen: usize = 1;
    switch (info) {
        0...23 => { slen = info; },
        24 => {
            if (pos + 1 >= buf.len) return error.EndOfBuffer;
            slen = buf[pos + 1];
            hlen = 2;
        },
        else => return error.InvalidCbor,
    }
    const start = pos + hlen;
    const end = start + @as(usize, @intCast(slen));
    if (end > buf.len) return error.EndOfBuffer;
    return .{ .key = buf[start..end], .len = hlen + @as(usize, @intCast(slen)) };
}

// ── Envelope type detection ────────────────────────────────────────────────────

/// Detect the "type" field from the core map of a dCBOR envelope.
/// Returns a stack-local slice (borrowed from buf) or null if unreadable.
fn detectEnvelopeType(buf: []const u8) ?[]const u8 {
    var pos: usize = 0;
    // Skip outer tag(200)
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else {
        return null;
    }
    // Array
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return null;
    const arr_info = buf[pos] & 0x1f;
    var arr_hlen: usize = 1;
    if (arr_info == 24) {
        arr_hlen = 2;
    } else if (arr_info > 23) return null;
    pos += arr_hlen;
    // Skip tag(201) for core
    if (pos + 1 < buf.len and buf[pos] == 0xD8 and buf[pos + 1] == 0xC9) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    }
    // Core map
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_MAP) return null;
    const map_info = buf[pos] & 0x1f;
    var map_count: u64 = 0;
    var map_hlen: usize = 1;
    switch (map_info) {
        0...23 => { map_count = map_info; },
        24 => {
            if (pos + 1 >= buf.len) return null;
            map_count = buf[pos + 1];
            map_hlen = 2;
        },
        else => return null,
    }
    pos += map_hlen;
    for (0..@as(usize, @intCast(map_count))) |_| {
        if (pos >= buf.len) break;
        const k = readTstr(buf, pos) catch break;
        pos += k.len;
        if (std.mem.eql(u8, k.key, "type")) {
            // Value is a tstr
            const v = readTstr(buf, pos) catch break;
            return v.key;
        }
        pos += skipCborItem(buf, pos) catch break;
    }
    return null;
}

/// Detect "field-kind" attribute from subsequent attribute arrays.
/// Returns a slice into buf or null.
fn detectFieldKind(buf: []const u8) ?[]const u8 {
    var pos: usize = 0;
    // Skip outer tag(200)
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return null;
    // Array header
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return null;
    const arr_info = buf[pos] & 0x1f;
    var arr_count: u64 = 0;
    var arr_hlen: usize = 1;
    switch (arr_info) {
        0...23 => { arr_count = arr_info; },
        24 => {
            if (pos + 1 >= buf.len) return null;
            arr_count = buf[pos + 1];
            arr_hlen = 2;
        },
        else => return null,
    }
    pos += arr_hlen;
    // Skip first element (core)
    pos += skipCborItem(buf, pos) catch return null;
    // Scan remaining attribute arrays
    for (1..@as(usize, @intCast(arr_count))) |_| {
        if (pos >= buf.len) break;
        if ((buf[pos] & 0xe0) != CBOR_MAJOR_ARR or (buf[pos] & 0x1f) != 2) {
            pos += skipCborItem(buf, pos) catch break;
            continue;
        }
        pos += 1; // array(2) header
        const lbl = readTstr(buf, pos) catch {
            pos += skipCborItem(buf, pos) catch break;
            pos += skipCborItem(buf, pos) catch break;
            continue;
        };
        pos += lbl.len;
        if (std.mem.eql(u8, lbl.key, "field-kind")) {
            const v = readTstr(buf, pos) catch break;
            return v.key;
        }
        pos += skipCborItem(buf, pos) catch break;
    }
    return null;
}

// ── Mythos field extraction ────────────────────────────────────────────────────

const MythosInfo = struct {
    body: []const u8 = "",
    true_name: ?[]const u8 = null,
    is_genesis: bool = false,
};

fn parseMythosInfo(buf: []const u8) MythosInfo {
    var info = MythosInfo{};
    var pos: usize = 0;
    // Skip outer tag(200)
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return info;
    // Array header
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return info;
    const arr_info = buf[pos] & 0x1f;
    var arr_count: u64 = 0;
    var arr_hlen: usize = 1;
    switch (arr_info) {
        0...23 => { arr_count = arr_info; },
        24 => {
            if (pos + 1 >= buf.len) return info;
            arr_count = buf[pos + 1];
            arr_hlen = 2;
        },
        else => return info,
    }
    pos += arr_hlen;
    // Skip tag(201) for core
    if (pos + 1 < buf.len and buf[pos] == 0xD8 and buf[pos + 1] == 0xC9) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    }
    // Core map
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_MAP) return info;
    const map_info_byte = buf[pos] & 0x1f;
    var map_count: u64 = 0;
    var map_hlen: usize = 1;
    switch (map_info_byte) {
        0...23 => { map_count = map_info_byte; },
        24 => {
            if (pos + 1 >= buf.len) return info;
            map_count = buf[pos + 1];
            map_hlen = 2;
        },
        else => return info,
    }
    pos += map_hlen;
    for (0..@as(usize, @intCast(map_count))) |_| {
        if (pos >= buf.len) break;
        const k = readTstr(buf, pos) catch break;
        pos += k.len;
        if (std.mem.eql(u8, k.key, "is-genesis")) {
            if (pos < buf.len) {
                info.is_genesis = buf[pos] == CBOR_SIMPLE_TRUE;
                pos += skipCborItem(buf, pos) catch break;
            }
        } else {
            pos += skipCborItem(buf, pos) catch break;
        }
    }
    // Scan attribute arrays for "body" and "true-name"
    for (1..@as(usize, @intCast(arr_count))) |_| {
        if (pos >= buf.len) break;
        if ((buf[pos] & 0xe0) != CBOR_MAJOR_ARR or (buf[pos] & 0x1f) != 2) {
            pos += skipCborItem(buf, pos) catch break;
            continue;
        }
        pos += 1; // array(2) header
        const lbl = readTstr(buf, pos) catch {
            pos += skipCborItem(buf, pos) catch break;
            pos += skipCborItem(buf, pos) catch break;
            continue;
        };
        pos += lbl.len;
        if (std.mem.eql(u8, lbl.key, "body")) {
            const v = readTstr(buf, pos) catch {
                pos += skipCborItem(buf, pos) catch break;
                continue;
            };
            info.body = v.key;
            pos += v.len;
        } else if (std.mem.eql(u8, lbl.key, "true-name")) {
            const v = readTstr(buf, pos) catch {
                pos += skipCborItem(buf, pos) catch break;
                continue;
            };
            info.true_name = v.key;
            pos += v.len;
        } else {
            pos += skipCborItem(buf, pos) catch break;
        }
    }
    return info;
}

// ── Timeline head-hashes extraction ───────────────────────────────────────────

/// Extract head_hashes from a jelly.timeline envelope.
/// Returns a slice of 32-byte arrays allocated from gpa.
fn parseTimelineHeadHashes(gpa: Allocator, buf: []const u8) ![][32]u8 {
    var result: std.ArrayList([32]u8) = .empty;
    errdefer result.deinit(gpa);

    var pos: usize = 0;
    // Skip tag(200)
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return result.toOwnedSlice(gpa);
    // Array
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return result.toOwnedSlice(gpa);
    const arr_info = buf[pos] & 0x1f;
    var arr_count: u64 = 0;
    var arr_hlen: usize = 1;
    switch (arr_info) {
        0...23 => { arr_count = arr_info; },
        24 => {
            if (pos + 1 >= buf.len) return result.toOwnedSlice(gpa);
            arr_count = buf[pos + 1];
            arr_hlen = 2;
        },
        else => return result.toOwnedSlice(gpa),
    }
    pos += arr_hlen;
    // Skip core (first element)
    pos += skipCborItem(buf, pos) catch return result.toOwnedSlice(gpa);
    // Scan attributes for "head-hashes"
    for (1..@as(usize, @intCast(arr_count))) |_| {
        if (pos >= buf.len) break;
        if ((buf[pos] & 0xe0) != CBOR_MAJOR_ARR or (buf[pos] & 0x1f) != 2) {
            pos += skipCborItem(buf, pos) catch break;
            continue;
        }
        pos += 1;
        const lbl = readTstr(buf, pos) catch {
            pos += skipCborItem(buf, pos) catch break;
            pos += skipCborItem(buf, pos) catch break;
            continue;
        };
        pos += lbl.len;
        if (std.mem.eql(u8, lbl.key, "head-hashes")) {
            // Value: array of bstr[32]
            if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) {
                pos += skipCborItem(buf, pos) catch break;
                continue;
            }
            const ha_info = buf[pos] & 0x1f;
            var ha_count: u64 = 0;
            var ha_hlen: usize = 1;
            switch (ha_info) {
                0...23 => { ha_count = ha_info; },
                24 => {
                    if (pos + 1 >= buf.len) break;
                    ha_count = buf[pos + 1];
                    ha_hlen = 2;
                },
                else => break,
            }
            pos += ha_hlen;
            for (0..@as(usize, @intCast(ha_count))) |_| {
                if (pos >= buf.len) break;
                const vib = buf[pos];
                if ((vib & 0xe0) != CBOR_MAJOR_BSTR) {
                    pos += skipCborItem(buf, pos) catch break;
                    continue;
                }
                const vi = vib & 0x1f;
                var vlen: usize = 0;
                var vhlen: usize = 1;
                if (vi <= 23) {
                    vlen = vi;
                } else if (vi == 24) {
                    if (pos + 1 >= buf.len) break;
                    vlen = buf[pos + 1];
                    vhlen = 2;
                }
                if (vlen == 32) {
                    const vstart = pos + vhlen;
                    if (vstart + 32 <= buf.len) {
                        var fp: [32]u8 = undefined;
                        @memcpy(&fp, buf[vstart .. vstart + 32]);
                        try result.append(gpa, fp);
                    }
                }
                pos += vhlen + vlen;
            }
        } else {
            pos += skipCborItem(buf, pos) catch break;
        }
    }
    return result.toOwnedSlice(gpa);
}

// ── DreamBall "contains" fingerprint extraction ────────────────────────────────

/// Extract the list of 32-byte "contains" fps from a DreamBall field envelope.
/// The DreamBall format stores contains directly in the core CBOR map.
/// Returns gpa-allocated slice.
fn parseDreamBallContains(gpa: Allocator, bytes: []const u8) ![][32]u8 {
    var result: std.ArrayList([32]u8) = .empty;
    errdefer result.deinit(gpa);

    // Use dreamball's own decoder
    const db = dreamball.envelope.decodeDreamBallSubject(bytes) catch return result.toOwnedSlice(gpa);
    for (db.contains) |fp| {
        try result.append(gpa, fp.bytes);
    }
    return result.toOwnedSlice(gpa);
}

// ── Room info extraction ───────────────────────────────────────────────────────

const RoomInfo = struct {
    fp: [32]u8,
    name: []const u8,
    item_count: usize,
};

/// Extract "name" from a jelly.dreamball.field (room) envelope via its attributes.
fn extractRoomName(buf: []const u8) []const u8 {
    var pos: usize = 0;
    // Skip tag(200)
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return "";
    // Array
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return "";
    const arr_info = buf[pos] & 0x1f;
    var arr_count: u64 = 0;
    var arr_hlen: usize = 1;
    switch (arr_info) {
        0...23 => { arr_count = arr_info; },
        24 => {
            if (pos + 1 >= buf.len) return "";
            arr_count = buf[pos + 1];
            arr_hlen = 2;
        },
        else => return "",
    }
    pos += arr_hlen;
    // Skip core
    pos += skipCborItem(buf, pos) catch return "";
    // Scan attributes
    for (1..@as(usize, @intCast(arr_count))) |_| {
        if (pos >= buf.len) break;
        if ((buf[pos] & 0xe0) != CBOR_MAJOR_ARR or (buf[pos] & 0x1f) != 2) {
            pos += skipCborItem(buf, pos) catch break;
            continue;
        }
        pos += 1;
        const lbl = readTstr(buf, pos) catch {
            pos += skipCborItem(buf, pos) catch break;
            pos += skipCborItem(buf, pos) catch break;
            continue;
        };
        pos += lbl.len;
        if (std.mem.eql(u8, lbl.key, "name")) {
            const v = readTstr(buf, pos) catch break;
            return v.key;
        }
        pos += skipCborItem(buf, pos) catch break;
    }
    return "";
}

// ── CAS file reading ───────────────────────────────────────────────────────────

/// Read envelope bytes for a fp from the palace CAS directory.
fn casRead(gpa: Allocator, cas_path: []const u8, fp: *const [32]u8) ?[]u8 {
    const hex = palace_mint.hexArray(fp);
    const path = std.fmt.allocPrint(gpa, "{s}/{s}", .{ cas_path, &hex }) catch return null;
    defer gpa.free(path);
    return helpers.readFile(gpa, path) catch null;
}

// ── Palace topology ────────────────────────────────────────────────────────────

pub const PalaceTopology = struct {
    mythos_head_body: []const u8,
    true_name: ?[]const u8,
    rooms: []RoomInfo,
    timeline_head_hashes: [][32]u8,
    oracle_fp: [32]u8,

    pub fn deinit(self: *PalaceTopology, gpa: Allocator) void {
        gpa.free(self.mythos_head_body);
        if (self.true_name) |tn| gpa.free(tn);
        for (self.rooms) |r| gpa.free(r.name);
        gpa.free(self.rooms);
        gpa.free(self.timeline_head_hashes);
    }
};

/// Load palace topology from bundle + CAS.
fn loadTopology(gpa: Allocator, palace_path: []const u8) !struct { topo: PalaceTopology, palace_fp: [32]u8 } {
    const bundle_path = try std.fmt.allocPrint(gpa, "{s}.bundle", .{palace_path});
    defer gpa.free(bundle_path);
    const bundle_bytes = helpers.readFile(gpa, bundle_path) catch {
        try io.writeAllStderr("error: cannot read palace bundle\n");
        return error.NoPalace;
    };
    defer gpa.free(bundle_bytes);

    const cas_path = try std.fmt.allocPrint(gpa, "{s}.cas", .{palace_path});
    defer gpa.free(cas_path);

    // Parse fps from bundle
    var fps: std.ArrayList([32]u8) = .empty;
    defer fps.deinit(gpa);
    var lines = std.mem.splitScalar(u8, bundle_bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len != 64) continue;
        var fp: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&fp, trimmed) catch continue;
        try fps.append(gpa, fp);
    }
    if (fps.items.len == 0) return error.InvalidBundle;

    const palace_fp = fps.items[0];

    // Read palace envelope
    const palace_bytes = casRead(gpa, cas_path, &palace_fp) orelse {
        try io.writeAllStderr("error: palace envelope not in CAS\n");
        return error.NoPalace;
    };
    defer gpa.free(palace_bytes);

    // Verify it's actually a palace (field-kind == "palace")
    const fk = detectFieldKind(palace_bytes);
    if (fk == null or !std.mem.eql(u8, fk.?, "palace")) {
        try io.writeAllStderr("not a palace\n");
        return error.NotAPalace;
    }

    // Get contains list
    const contains_fps = try parseDreamBallContains(gpa, palace_bytes);
    defer gpa.free(contains_fps);

    // Scan contains for oracle (agent), mythos, timeline, rooms
    var oracle_fp: [32]u8 = [_]u8{0} ** 32;
    var mythos_head_fp: ?[32]u8 = null;
    var timeline_fp: ?[32]u8 = null;

    var rooms_list: std.ArrayList(RoomInfo) = .empty;
    errdefer rooms_list.deinit(gpa);

    for (contains_fps) |cfp| {
        const cbytes = casRead(gpa, cas_path, &cfp) orelse continue;
        defer gpa.free(cbytes);
        const env_type = detectEnvelopeType(cbytes) orelse continue;
        if (std.mem.eql(u8, env_type, "jelly.dreamball.agent")) {
            @memcpy(&oracle_fp, &cfp);
        } else if (std.mem.eql(u8, env_type, "jelly.mythos")) {
            mythos_head_fp = cfp;
        } else if (std.mem.eql(u8, env_type, "jelly.timeline")) {
            timeline_fp = cfp;
        } else if (std.mem.eql(u8, env_type, "jelly.dreamball.field")) {
            // Could be a room
            const room_fk = detectFieldKind(cbytes) orelse "";
            if (std.mem.eql(u8, room_fk, "room")) {
                const room_name_raw = extractRoomName(cbytes);
                // Dupe name before cbytes is freed — extractRoomName returns a slice into cbytes.
                const room_name = try gpa.dupe(u8, room_name_raw);
                errdefer gpa.free(room_name);
                // Get item count from room's contains
                const room_contains = try parseDreamBallContains(gpa, cbytes);
                defer gpa.free(room_contains);
                try rooms_list.append(gpa, RoomInfo{
                    .fp = cfp,
                    .name = room_name,
                    .item_count = room_contains.len,
                });
            }
        }
    }

    // Walk all bundle fps for rooms and timeline if not found in direct contains
    // (rooms added after mint appear in subsequent action lines in bundle, not in palace.contains)
    for (fps.items[1..]) |bfp| {
        const cbytes = casRead(gpa, cas_path, &bfp) orelse continue;
        defer gpa.free(cbytes);
        const env_type = detectEnvelopeType(cbytes) orelse continue;
        if (std.mem.eql(u8, env_type, "jelly.mythos")) {
            // Use last mythos seen in bundle as the head
            mythos_head_fp = bfp;
        } else if (std.mem.eql(u8, env_type, "jelly.timeline")) {
            timeline_fp = bfp;
        } else if (std.mem.eql(u8, env_type, "jelly.dreamball.field")) {
            const room_fk = detectFieldKind(cbytes) orelse "";
            if (std.mem.eql(u8, room_fk, "room")) {
                // Only add if not already present
                var already = false;
                for (rooms_list.items) |r| {
                    if (std.mem.eql(u8, &r.fp, &bfp)) { already = true; break; }
                }
                if (!already) {
                    const room_name_raw = extractRoomName(cbytes);
                    // Dupe name before cbytes is freed.
                    const room_name = try gpa.dupe(u8, room_name_raw);
                    errdefer gpa.free(room_name);
                    const room_contains = try parseDreamBallContains(gpa, cbytes);
                    defer gpa.free(room_contains);
                    try rooms_list.append(gpa, RoomInfo{
                        .fp = bfp,
                        .name = room_name,
                        .item_count = room_contains.len,
                    });
                }
            }
        }
    }

    // Parse mythos info — duped slices are owned by PalaceTopology.deinit.
    var mythos_head_body: []const u8 = try gpa.dupe(u8, "(none)");
    var true_name: ?[]const u8 = null;
    if (mythos_head_fp) |mfp| {
        const mbytes = casRead(gpa, cas_path, &mfp) orelse null;
        if (mbytes) |mb| {
            defer gpa.free(mb);
            const mi = parseMythosInfo(mb);
            // Dupe body/true_name before mb is freed — parseMythosInfo returns slices
            // pointing into mb; using them after free is UB.
            if (mi.body.len > 0) {
                gpa.free(mythos_head_body);
                mythos_head_body = try gpa.dupe(u8, mi.body);
            }
            if (mi.true_name) |tn| {
                true_name = try gpa.dupe(u8, tn);
            }
        }
    }

    // Parse timeline head hashes
    var timeline_head_hashes: [][32]u8 = &.{};
    if (timeline_fp) |tfp| {
        const tbytes = casRead(gpa, cas_path, &tfp) orelse null;
        if (tbytes) |tb| {
            defer gpa.free(tb);
            timeline_head_hashes = try parseTimelineHeadHashes(gpa, tb);
        }
    }

    return .{
        .topo = PalaceTopology{
            .mythos_head_body = mythos_head_body,
            .true_name = true_name,
            .rooms = try rooms_list.toOwnedSlice(gpa),
            .timeline_head_hashes = timeline_head_hashes,
            .oracle_fp = oracle_fp,
        },
        .palace_fp = palace_fp,
    };
}

// ── run (entry point for `jelly show --as-palace <path>`) ─────────────────────

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(2) or parsed.positional.items.len == 0) {
        try io.writeAllStdout(
            \\jelly show --as-palace <palace> [--json] [--archiforms]
            \\
            \\Show palace topology. <palace> is the path prefix (without .bundle).
            \\
            \\  --json        Output structured JSON
            \\  --archiforms  List the 19 seed archiform names
            \\
        );
        return 0;
    }

    const want_json = parsed.flag(0);
    const want_archiforms = parsed.flag(1);
    const palace_path = parsed.positional.items[0];

    // AC4: --archiforms just lists names (independent of palace path)
    if (want_archiforms) {
        for (ARCHIFORMS) |af| {
            try io.printStdout("{s}\n", .{af});
        }
        return 0;
    }

    // Load topology
    const result = loadTopology(gpa, palace_path) catch |err| switch (err) {
        error.NotAPalace => return 1,
        error.NoPalace => return 2,
        error.InvalidBundle => {
            try io.writeAllStderr("error: invalid palace bundle\n");
            return 2;
        },
        else => return err,
    };
    var topo = result.topo;
    defer topo.deinit(gpa);

    const oracle_hex = palace_mint.hexArray(&topo.oracle_fp);

    if (want_json) {
        // AC2: JSON output
        try io.writeAllStdout("{");
        try io.printStdout("\"mythosHeadBody\":", .{});
        try writeJsonString(topo.mythos_head_body);
        try io.printStdout(",\"trueName\":", .{});
        if (topo.true_name) |tn| {
            try writeJsonString(tn);
        } else {
            try io.writeAllStdout("null");
        }
        try io.writeAllStdout(",\"rooms\":[");
        for (topo.rooms, 0..) |r, i| {
            if (i > 0) try io.writeAllStdout(",");
            const room_hex = palace_mint.hexArray(&r.fp);
            try io.printStdout("{{\"fp\":\"{s}\",\"name\":", .{&room_hex});
            try writeJsonString(r.name);
            try io.printStdout(",\"itemCount\":{d}}}", .{r.item_count});
        }
        try io.writeAllStdout("],\"timelineHeadHashes\":[");
        for (topo.timeline_head_hashes, 0..) |hh, i| {
            if (i > 0) try io.writeAllStdout(",");
            const hh_hex = palace_mint.hexArray(&hh);
            try io.printStdout("\"{s}\"", .{&hh_hex});
        }
        try io.printStdout("],\"oracleFp\":\"{s}\"", .{&oracle_hex});
        try io.writeAllStdout("}\n");
        return 0;
    }

    // AC1: human-readable output
    try io.printStdout("Palace: {s}\n", .{palace_path});
    try io.printStdout("  mythos:      {s}\n", .{topo.mythos_head_body});
    if (topo.true_name) |tn| {
        try io.printStdout("  true-name:   {s}\n", .{tn});
    }
    try io.printStdout("  rooms ({d}):\n", .{topo.rooms.len});
    for (topo.rooms) |r| {
        const room_hex = palace_mint.hexArray(&r.fp);
        try io.printStdout("    [{s}] {s} ({d} items)\n", .{ room_hex[0..8], r.name, r.item_count });
    }
    try io.printStdout("  timeline head-hashes ({d}):\n", .{topo.timeline_head_hashes.len});
    for (topo.timeline_head_hashes) |hh| {
        const hh_hex = palace_mint.hexArray(&hh);
        try io.printStdout("    {s}\n", .{&hh_hex});
    }
    try io.printStdout("  oracle fp:   {s}\n", .{&oracle_hex});
    return 0;
}

/// `jelly palace show --archiforms` entry point (called from palace.zig).
pub fn runArchiforms(gpa: Allocator, _argv: [][:0]const u8) !u8 {
    _ = gpa;
    _ = _argv;
    for (ARCHIFORMS) |af| {
        try io.printStdout("{s}\n", .{af});
    }
    return 0;
}

/// Write a JSON-encoded string to stdout.
fn writeJsonString(s: []const u8) !void {
    try io.writeAllStdout("\"");
    for (s) |c| {
        switch (c) {
            '"' => try io.writeAllStdout("\\\""),
            '\\' => try io.writeAllStdout("\\\\"),
            '\n' => try io.writeAllStdout("\\n"),
            '\r' => try io.writeAllStdout("\\r"),
            '\t' => try io.writeAllStdout("\\t"),
            else => {
                var buf: [1]u8 = .{c};
                try io.writeAllStdout(&buf);
            },
        }
    }
    try io.writeAllStdout("\"");
}

// ── Hex decode helper ──────────────────────────────────────────────────────────

fn hexDecode(s: []const u8) !([32]u8) {
    var out: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&out, s);
    return out;
}

// ============================================================================
// Tests (AC12 — ≥5 test blocks)
// ============================================================================

test "ARCHIFORMS has exactly 19 entries" {
    try std.testing.expectEqual(@as(usize, 19), ARCHIFORMS.len);
}

test "ARCHIFORMS contains all expected seed forms" {
    const expected = [_][]const u8{
        "library", "forge", "throne-room", "garden", "courtyard",
        "lab", "crypt", "portal", "atrium", "cell",
        "scroll", "lantern", "vessel", "compass", "seed",
        "muse", "judge", "midwife", "trickster",
    };
    try std.testing.expectEqual(expected.len, ARCHIFORMS.len);
    for (ARCHIFORMS, expected) |got, want| {
        try std.testing.expectEqualStrings(want, got);
    }
}

test "detectEnvelopeType: handles empty buffer gracefully" {
    const result = detectEnvelopeType(&.{});
    try std.testing.expect(result == null);
}

test "detectFieldKind: returns null on minimal DreamBall without field-kind attr" {
    // A minimal DreamBall fixture should not have a field-kind attribute.
    // Use the golden fixture from src/golden.zig (embedded directly here as a
    // hand-crafted minimal envelope).
    // tag(200) array(1) tag(201) map(2) "type" "jelly.dreamball" "format-version" 2
    const minimal: []const u8 = &[_]u8{
        0xD8, 0xC8, // tag(200)
        0x81,       // array(1)
        0xD8, 0xC9, // tag(201)
        0xA2,       // map(2)
        0x64, 't', 'y', 'p', 'e', // "type"
        0x6F, 'j', 'e', 'l', 'l', 'y', '.', 'd', 'r', 'e', 'a', 'm', 'b', 'a', 'l', 'l', // "jelly.dreamball"
        0x6E, 'f', 'o', 'r', 'm', 'a', 't', '-', 'v', 'e', 'r', 's', 'i', 'o', 'n', // "format-version"
        0x02, // 2
    };
    const fk = detectFieldKind(minimal);
    try std.testing.expect(fk == null);
}

test "parseTimelineHeadHashes: empty timeline returns empty slice" {
    const allocator = std.testing.allocator;
    // Minimal timeline: tag(200) array(1) tag(201) map(2) "type" "jelly.timeline" "format-version" 3
    const minimal: []const u8 = &[_]u8{
        0xD8, 0xC8, // tag(200)
        0x81,       // array(1)
        0xD8, 0xC9, // tag(201)
        0xA2,       // map(2)
        0x64, 't', 'y', 'p', 'e', // "type"
        0x6E, 'j', 'e', 'l', 'l', 'y', '.', 't', 'i', 'm', 'e', 'l', 'i', 'n', 'e', // "jelly.timeline"
        0x6E, 'f', 'o', 'r', 'm', 'a', 't', '-', 'v', 'e', 'r', 's', 'i', 'o', 'n', // "format-version"
        0x03, // 3
    };
    const hashes = try parseTimelineHeadHashes(allocator, minimal);
    defer allocator.free(hashes);
    try std.testing.expectEqual(@as(usize, 0), hashes.len);
}

test "hexDecode roundtrip" {
    const input: [32]u8 = [_]u8{ 0xAB } ** 32;
    const hex = palace_mint.hexArray(&input);
    const decoded = try hexDecode(&hex);
    try std.testing.expectEqualSlices(u8, &input, &decoded);
}
