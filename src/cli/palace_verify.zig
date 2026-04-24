//! `jelly verify <palace>` — palace **structural** invariant checker.
//!
//! When the target is a palace bundle (detected by field-kind == "palace"),
//! verify.zig routes here. Six invariants are checked:
//!
//!   (a) AC5: ≥1 direct room — palace contains at least one jelly.dreamball.field
//!       with field-kind == "room".
//!   (b) AC6: oracle is sole direct Agent — exactly one jelly.dreamball.agent
//!       directly contained; second one is rejected.
//!   (c) AC7: action parent-hashes resolve — every jelly.action in the bundle
//!       has parent-hashes that are all resolvable within the CAS.
//!   (d) AC8: mythos chain to single genesis — via mythos-chain.walkToGenesis
//!       (imported directly, NOT copied; S3.4 AC6 contract).
//!   (e) AC9: head-hashes are timeline leaves — every fp in the timeline's
//!       head-hashes must be a jelly.action in CAS that is not referenced as a
//!       parent by any other action in the bundle (i.e., truly a leaf).
//!   (f) AC10: oracle actor-fp — every action whose actor fp equals the oracle
//!       fp must match the oracle fp derived from the oracle key file.
//!
//! Distinct stderr messages are used per invariant so callers can identify
//! which constraint failed (required by spec per AC5–AC10 language).
//!
//! ## NOT VERIFIED IN MVP — cryptographic signature check over action envelopes
//!
//! Invariants (a)–(f) are **structural**. This file does NOT verify the
//! ed25519 + ML-DSA dual signatures carried in `jelly.action.signatures`
//! against any signer public key. An attacker with CAS-write access can
//! forge an action whose `actor` fp matches the oracle fp; verify will
//! pass it. The MVP threat model (local-first, single-custodian per D-011)
//! treats CAS-write as equivalent to oracle-possession, which is a weaker
//! guarantee than what multi-custodian palaces will need.
//!
//! This limitation is tracked in `docs/known-gaps.md §11`. The next sprint
//! adds invariant (g) "action signatures verify against actor public key"
//! via a new call to `dreamball.signer.verify` over canonical action bytes.
//! Depends on known-gaps §8 (parameterised WASM signer export) for browser
//! parity.
//!
//! TODO-CRYPTO: action-envelope signature verification deferred — see
//! docs/known-gaps.md §11.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const helpers = @import("helpers.zig");
const palace_mint = @import("palace_mint.zig");
// AC8: walkToGenesis imported directly from dreamball.mythos_chain (no copy; S3.4 AC6 contract).
const mythos_chain = dreamball.mythos_chain;

// ── Minimal CBOR scanner (palace-local; same approach as palace_show.zig) ─────

const CBOR_MAJOR_BSTR: u8 = 0x40;
const CBOR_MAJOR_TSTR: u8 = 0x60;
const CBOR_MAJOR_ARR: u8 = 0x80;
const CBOR_MAJOR_MAP: u8 = 0xa0;
const CBOR_MAJOR_TAG: u8 = 0xc0;
const CBOR_SIMPLE_TRUE: u8 = 0xf5;

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
        CBOR_MAJOR_TAG => return header_len + try skipCborItem(buf, pos + header_len),
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

// ── Envelope type + field-kind detection ──────────────────────────────────────

fn detectEnvelopeType(buf: []const u8) ?[]const u8 {
    var pos: usize = 0;
    // Skip tag(200)
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return null;
    // Array header
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return null;
    const arr_info = buf[pos] & 0x1f;
    var arr_hlen: usize = 1;
    if (arr_info == 24) arr_hlen = 2 else if (arr_info > 23) return null;
    pos += arr_hlen;
    // Skip tag(201)
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
            const v = readTstr(buf, pos) catch break;
            return v.key;
        }
        pos += skipCborItem(buf, pos) catch break;
    }
    return null;
}

fn detectFieldKind(buf: []const u8) ?[]const u8 {
    var pos: usize = 0;
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return null;
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
    pos += skipCborItem(buf, pos) catch return null;
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
        if (std.mem.eql(u8, lbl.key, "field-kind")) {
            const v = readTstr(buf, pos) catch break;
            return v.key;
        }
        pos += skipCborItem(buf, pos) catch break;
    }
    return null;
}

// ── Action parent-hashes extraction ───────────────────────────────────────────

/// Extract parent-hashes from a jelly.action envelope. Returns gpa-owned slice.
fn parseActionParentHashes(gpa: Allocator, buf: []const u8) ![][32]u8 {
    var result: std.ArrayList([32]u8) = .empty;
    errdefer result.deinit(gpa);

    var pos: usize = 0;
    // Skip tag(200)
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return result.toOwnedSlice(gpa);
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
    // Skip tag(201)
    if (pos + 1 < buf.len and buf[pos] == 0xD8 and buf[pos + 1] == 0xC9) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    }
    // Core map — find "parent-hashes"
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_MAP) return result.toOwnedSlice(gpa);
    const map_info = buf[pos] & 0x1f;
    var map_count: u64 = 0;
    var map_hlen: usize = 1;
    switch (map_info) {
        0...23 => { map_count = map_info; },
        24 => {
            if (pos + 1 >= buf.len) return result.toOwnedSlice(gpa);
            map_count = buf[pos + 1];
            map_hlen = 2;
        },
        else => return result.toOwnedSlice(gpa),
    }
    pos += map_hlen;
    for (0..@as(usize, @intCast(map_count))) |_| {
        if (pos >= buf.len) break;
        const k = readTstr(buf, pos) catch break;
        pos += k.len;
        if (std.mem.eql(u8, k.key, "parent-hashes")) {
            // Value: array of bstr[32]
            if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) break;
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
            break;
        }
        pos += skipCborItem(buf, pos) catch break;
    }
    return result.toOwnedSlice(gpa);
}

/// Extract the actor field (32-byte bstr) from a jelly.action envelope core map.
fn parseActionActor(buf: []const u8) ?[32]u8 {
    var pos: usize = 0;
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return null;
    if (pos >= buf.len or (buf[pos] & 0xe0) != CBOR_MAJOR_ARR) return null;
    const arr_info = buf[pos] & 0x1f;
    var arr_hlen: usize = 1;
    if (arr_info == 24) arr_hlen = 2 else if (arr_info > 23) return null;
    pos += arr_hlen;
    if (pos + 1 < buf.len and buf[pos] == 0xD8 and buf[pos + 1] == 0xC9) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    }
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
        if (std.mem.eql(u8, k.key, "actor")) {
            if (pos >= buf.len) break;
            const vib = buf[pos];
            if ((vib & 0xe0) != CBOR_MAJOR_BSTR) break;
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
                    var actor: [32]u8 = undefined;
                    @memcpy(&actor, buf[vstart .. vstart + 32]);
                    return actor;
                }
            }
            break;
        }
        pos += skipCborItem(buf, pos) catch break;
    }
    return null;
}

/// Extract head-hashes from a jelly.timeline envelope.
fn parseTimelineHeadHashes(gpa: Allocator, buf: []const u8) ![][32]u8 {
    var result: std.ArrayList([32]u8) = .empty;
    errdefer result.deinit(gpa);
    var pos: usize = 0;
    if (pos + 1 < buf.len and buf[pos] == 0xD8) {
        pos += 2;
    } else if (pos < buf.len and (buf[pos] & 0xe0) == CBOR_MAJOR_TAG) {
        pos += 1;
    } else return result.toOwnedSlice(gpa);
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
    pos += skipCborItem(buf, pos) catch return result.toOwnedSlice(gpa);
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
                if (vi <= 23) { vlen = vi; }
                else if (vi == 24) {
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

// ── CAS helpers ────────────────────────────────────────────────────────────────

fn casRead(gpa: Allocator, cas_path: []const u8, fp: *const [32]u8) ?[]u8 {
    const hex = palace_mint.hexArray(fp);
    const path = std.fmt.allocPrint(gpa, "{s}/{s}", .{ cas_path, &hex }) catch return null;
    defer gpa.free(path);
    return helpers.readFile(gpa, path) catch null;
}

// ── CAS lookup adapter for walkToGenesis ──────────────────────────────────────

const CasContext = struct {
    gpa: Allocator,
    cas_path: []const u8,
    // Bytes are retained in the walk-scoped arena for the duration of one
    // verify invocation. walkToGenesis consumes each slice only to extract the
    // predecessor fp, but the resulting `[]const u8` returned to the caller
    // must remain valid until the walk terminates. Retention is bounded by
    // mythos-chain length (MVP: single-digit) × envelope size (~KBs), well
    // under any practical memory ceiling. If chains grow, switch to per-node
    // free-after-predecessor-extraction; today the arena discipline is cheaper
    // than the alternative plumbing.
    arena: std.heap.ArenaAllocator,

    fn lookup(fp: *const [32]u8, userdata: ?*anyopaque) ?[]const u8 {
        const ctx: *CasContext = @ptrCast(@alignCast(userdata.?));
        const hex = palace_mint.hexArray(fp);
        const path = std.fmt.allocPrint(ctx.arena.allocator(), "{s}/{s}", .{ ctx.cas_path, &hex }) catch return null;
        return helpers.readFile(ctx.arena.allocator(), path) catch null;
    }
};

// ── Main verify entry point ────────────────────────────────────────────────────

/// Verify palace invariants. Called by verify.zig when the target is a palace
/// bundle (field-kind == "palace"). `palace_path` is the path prefix (without
/// .bundle suffix).
pub fn run(gpa: Allocator, palace_path: []const u8) !u8 {
    const bundle_path = try std.fmt.allocPrint(gpa, "{s}.bundle", .{palace_path});
    defer gpa.free(bundle_path);
    const bundle_bytes = helpers.readFile(gpa, bundle_path) catch {
        try io.writeAllStderr("error: cannot read palace bundle\n");
        return 2;
    };
    defer gpa.free(bundle_bytes);

    const cas_path = try std.fmt.allocPrint(gpa, "{s}.cas", .{palace_path});
    defer gpa.free(cas_path);

    // Parse all fps from bundle
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
    if (fps.items.len == 0) {
        try io.writeAllStderr("error: invalid or empty palace bundle\n");
        return 2;
    }
    const palace_fp = fps.items[0];

    // Read the palace field envelope
    const palace_bytes = casRead(gpa, cas_path, &palace_fp) orelse {
        try io.writeAllStderr("error: palace envelope not in CAS\n");
        return 2;
    };
    defer gpa.free(palace_bytes);

    // Verify it's actually a palace
    const fk = detectFieldKind(palace_bytes);
    if (fk == null or !std.mem.eql(u8, fk.?, "palace")) {
        try io.writeAllStderr("not a palace\n");
        return 1;
    }

    // ── Load .oracle.key FIRST (MEDIUM-6 fix) ────────────────────────────────
    // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
    // Derive oracle_fp from the .oracle.key file's Ed25519 pubkey rather than
    // the first-seen Agent envelope (MEDIUM-6 code review fix).
    const oracle_key_path = try std.fmt.allocPrint(gpa, "{s}.oracle.key", .{palace_path});
    defer gpa.free(oracle_key_path);
    var oracle_fp: [32]u8 = [_]u8{0} ** 32;
    var oracle_key_loaded = false;
    {
        const oracle_keys = dreamball.key_file.readFromPath(gpa, oracle_key_path) catch null;
        if (oracle_keys) |ok| {
            oracle_fp = dreamball.fingerprint.Fingerprint.fromEd25519(ok.ed25519_public).bytes;
            oracle_key_loaded = true;
        }
    }

    // ── Scan all envelopes in bundle ──────────────────────────────────────────
    // Collect: rooms, agents, actions, timeline, first-seen agent fp.
    var room_count: usize = 0;
    var agent_count: usize = 0;
    var first_agent_fp: [32]u8 = [_]u8{0} ** 32;
    var mythos_head_fp: ?[32]u8 = null;
    var timeline_fp: ?[32]u8 = null;

    var action_fps: std.ArrayList([32]u8) = .empty;
    defer action_fps.deinit(gpa);
    var action_actors: std.ArrayList([32]u8) = .empty;
    defer action_actors.deinit(gpa);

    for (fps.items) |bfp| {
        const cbytes = casRead(gpa, cas_path, &bfp) orelse continue;
        defer gpa.free(cbytes);
        const env_type = detectEnvelopeType(cbytes) orelse continue;

        if (std.mem.eql(u8, env_type, "jelly.dreamball.agent")) {
            agent_count += 1;
            if (agent_count == 1) @memcpy(&first_agent_fp, &bfp);
        } else if (std.mem.eql(u8, env_type, "jelly.dreamball.field")) {
            const rfk = detectFieldKind(cbytes) orelse "";
            if (std.mem.eql(u8, rfk, "room")) {
                room_count += 1;
            }
        } else if (std.mem.eql(u8, env_type, "jelly.action")) {
            try action_fps.append(gpa, bfp);
            const actor = parseActionActor(cbytes) orelse [_]u8{0} ** 32;
            try action_actors.append(gpa, actor);
        } else if (std.mem.eql(u8, env_type, "jelly.mythos")) {
            mythos_head_fp = bfp;
        } else if (std.mem.eql(u8, env_type, "jelly.timeline")) {
            timeline_fp = bfp;
        }
    }

    // ── Invariant (a): ≥1 direct room ────────────────────────────────────────
    if (room_count == 0) {
        try io.writeAllStderr("error: palace has no rooms (invariant a: ≥1 direct room required)\n");
        return 1;
    }

    // ── Invariant (b): oracle is sole direct Agent AND its fp matches .oracle.key ──
    // TODO-CRYPTO: oracle key is plaintext (known-gaps §6)
    if (agent_count > 1) {
        try io.writeAllStderr("error: multiple Agents directly contained; exactly one (oracle) permitted (invariant b)\n");
        return 1;
    }
    if (oracle_key_loaded and agent_count == 1) {
        if (!std.mem.eql(u8, &first_agent_fp, &oracle_fp)) {
            const agent_hex = palace_mint.hexArray(&first_agent_fp);
            const oracle_hex = palace_mint.hexArray(&oracle_fp);
            try printStderr(
                "error: sole Agent envelope fp {s} does not match oracle-key-derived fp {s} (invariant b)\n",
                .{ &agent_hex, &oracle_hex },
            );
            return 1;
        }
    }

    // ── Invariant (c): action parent-hashes resolve ────────────────────────────
    for (action_fps.items) |afp| {
        const abytes = casRead(gpa, cas_path, &afp) orelse continue;
        defer gpa.free(abytes);
        const parents = try parseActionParentHashes(gpa, abytes);
        defer gpa.free(parents);
        for (parents) |parent_fp| {
            const pbytes = casRead(gpa, cas_path, &parent_fp);
            if (pbytes) |pb| {
                gpa.free(pb);
            } else {
                const afp_hex = palace_mint.hexArray(&afp);
                const pfp_hex = palace_mint.hexArray(&parent_fp);
                try printStderr(
                    "error: action {s} has unresolvable parent-hash {s} (invariant c)\n",
                    .{ &afp_hex, &pfp_hex },
                );
                return 1;
            }
        }
    }

    // ── Invariant (d): mythos chain to single genesis ─────────────────────────
    // Uses walkToGenesis directly from mythos-chain.zig (AC8: no copy).
    if (mythos_head_fp) |mhfp| {
        var cas_ctx = CasContext{
            .gpa = gpa,
            .cas_path = cas_path,
            .arena = std.heap.ArenaAllocator.init(gpa),
        };
        defer cas_ctx.arena.deinit();

        const genesis_result = mythos_chain.walkToGenesis(
            CasContext.lookup,
            &cas_ctx,
            &mhfp,
        );
        switch (genesis_result) {
            .ok => {}, // happy
            .unresolvable_predecessor => |broken_fp| {
                const hex = palace_mint.hexArray(&broken_fp);
                try printStderr(
                    "error: mythos chain has unresolvable predecessor at {s} (invariant d)\n",
                    .{&hex},
                );
                return 1;
            },
            .multiple_genesis => |mg| {
                const h1 = palace_mint.hexArray(&mg.first);
                const h2 = palace_mint.hexArray(&mg.second);
                try printStderr(
                    "error: mythos chain has multiple genesis nodes ({s}, {s}) (invariant d)\n",
                    .{ &h1, &h2 },
                );
                return 1;
            },
        }
    }

    // ── Invariant (e): head-hashes are timeline leaves ─────────────────────────
    if (timeline_fp) |tfp| {
        const tbytes = casRead(gpa, cas_path, &tfp) orelse {
            try io.writeAllStderr("error: timeline envelope not in CAS\n");
            return 1;
        };
        defer gpa.free(tbytes);

        const head_hashes = try parseTimelineHeadHashes(gpa, tbytes);
        defer gpa.free(head_hashes);

        // Build set of all parent-hashes referenced by any action in bundle.
        var referenced_as_parent = std.AutoHashMap([32]u8, void).init(gpa);
        defer referenced_as_parent.deinit();
        for (action_fps.items) |afp| {
            const abytes = casRead(gpa, cas_path, &afp) orelse continue;
            defer gpa.free(abytes);
            const parents = try parseActionParentHashes(gpa, abytes);
            defer gpa.free(parents);
            for (parents) |p| {
                try referenced_as_parent.put(p, {});
            }
        }

        for (head_hashes) |hh| {
            // Must be a jelly.action in CAS
            const hbytes = casRead(gpa, cas_path, &hh);
            if (hbytes) |hb| {
                defer gpa.free(hb);
                const ht = detectEnvelopeType(hb) orelse "";
                if (!std.mem.eql(u8, ht, "jelly.action")) {
                    const hex = palace_mint.hexArray(&hh);
                    try printStderr(
                        "error: head-hash {s} is not a jelly.action (invariant e)\n",
                        .{&hex},
                    );
                    return 1;
                }
                // Must not be referenced as a parent by another action (must be a leaf)
                if (referenced_as_parent.contains(hh)) {
                    const hex = palace_mint.hexArray(&hh);
                    try printStderr(
                        "error: head-hash {s} is not a leaf — it is referenced as parent by another action (invariant e)\n",
                        .{&hex},
                    );
                    return 1;
                }
            } else {
                const hex = palace_mint.hexArray(&hh);
                try printStderr(
                    "error: head-hash {s} not found in CAS (invariant e)\n",
                    .{&hex},
                );
                return 1;
            }
        }
    }

    // ── Invariant (f/AC10): oracle actor-fp provenance ─────────────────────────
    // TODO-CRYPTO: oracle key is plaintext (known-gaps §6)
    // oracle_fp was derived from the oracle key file at the top (MEDIUM-6).
    // Verify every action actor that claims oracle identity carries the key-derived fp.
    if (oracle_key_loaded) {
        for (action_fps.items, action_actors.items) |afp, actor| {
            if (std.mem.eql(u8, &actor, &oracle_fp)) {
                // Actor matches oracle — correct.
            } else if (std.mem.eql(u8, &actor, &first_agent_fp) and !std.mem.eql(u8, &first_agent_fp, &oracle_fp)) {
                // Actor matches envelope fp but not key-derived fp — mismatch.
                const afp_hex = palace_mint.hexArray(&afp);
                try printStderr(
                    "error: oracle actor fp mismatch on action {s} (AC10 / SEC11 provenance)\n",
                    .{&afp_hex},
                );
                return 1;
            }
        }
    }

    try io.writeAllStdout("palace ok\n");
    return 0;
}

// ── Public helper: detect if a bundle path is a palace ─────────────────────────

/// Returns true if the given path prefix points to a palace bundle
/// (the first fp in the bundle resolves to a field-kind == "palace" envelope).
pub fn isPalaceBundle(gpa: Allocator, path_prefix: []const u8) bool {
    const bundle_path = std.fmt.allocPrint(gpa, "{s}.bundle", .{path_prefix}) catch return false;
    defer gpa.free(bundle_path);
    const bundle_bytes = helpers.readFile(gpa, bundle_path) catch return false;
    defer gpa.free(bundle_bytes);

    const cas_path = std.fmt.allocPrint(gpa, "{s}.cas", .{path_prefix}) catch return false;
    defer gpa.free(cas_path);

    // First line = palace fp
    var it = std.mem.splitScalar(u8, bundle_bytes, '\n');
    const first_line = blk: {
        while (it.next()) |line| {
            const t = std.mem.trim(u8, line, " \t\r");
            if (t.len == 64) break :blk t;
        }
        break :blk "";
    };
    if (first_line.len != 64) return false;
    var palace_fp: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&palace_fp, first_line) catch return false;

    const pbytes = casRead(gpa, cas_path, &palace_fp) orelse return false;
    defer gpa.free(pbytes);
    const fk = detectFieldKind(pbytes) orelse return false;
    return std.mem.eql(u8, fk, "palace");
}

// ── printStderr helper ─────────────────────────────────────────────────────────

fn printStderr(comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch fmt;
    try io.writeAllStderr(msg);
}

// ============================================================================
// Tests (AC12 — ≥5 test blocks in palace_verify.zig)
// ============================================================================

test "detectEnvelopeType: returns null for empty buffer" {
    try std.testing.expect(detectEnvelopeType(&.{}) == null);
}

test "detectFieldKind: returns null for short buffer" {
    try std.testing.expect(detectFieldKind(&.{ 0xD8, 0xC8 }) == null);
}

test "parseActionParentHashes: empty parent-hashes array" {
    const allocator = std.testing.allocator;
    // A minimal action with empty parent-hashes.
    // tag(200) array(1) tag(201) map(4) "type" "jelly.action" "actor" bstr[32] "action-kind" "palace-minted" "parent-hashes" array(0) "format-version" 3
    // We use a hand-built buffer containing just the type field to check graceful empty result.
    const minimal: []const u8 = &[_]u8{
        0xD8, 0xC8, // tag(200)
        0x81,       // array(1)
        0xD8, 0xC9, // tag(201)
        0xA2,       // map(2)
        0x64, 't', 'y', 'p', 'e',
        0x6B, 'j', 'e', 'l', 'l', 'y', '.', 'a', 'c', 't', 'i', 'o', 'n', // "jelly.action"
        0x6E, 'p', 'a', 'r', 'e', 'n', 't', '-', 'h', 'a', 's', 'h', 'e', 's', // "parent-hashes"
        0x80, // array(0)
    };
    const hashes = try parseActionParentHashes(allocator, minimal);
    defer allocator.free(hashes);
    try std.testing.expectEqual(@as(usize, 0), hashes.len);
}

test "parseActionActor: returns null for empty buffer" {
    try std.testing.expect(parseActionActor(&.{}) == null);
}

test "isPalaceBundle: returns false for non-existent path" {
    const allocator = std.testing.allocator;
    const result = isPalaceBundle(allocator, "/tmp/definitely_not_a_palace_12345");
    try std.testing.expect(!result);
}

test "parseTimelineHeadHashes: returns empty slice for empty array in timeline" {
    const allocator = std.testing.allocator;
    const minimal: []const u8 = &[_]u8{
        0xD8, 0xC8, // tag(200)
        0x81,       // array(1)
        0xD8, 0xC9, // tag(201)
        0xA2,       // map(2)
        0x64, 't', 'y', 'p', 'e',
        0x6E, 'j', 'e', 'l', 'l', 'y', '.', 't', 'i', 'm', 'e', 'l', 'i', 'n', 'e',
        0x6E, 'f', 'o', 'r', 'm', 'a', 't', '-', 'v', 'e', 'r', 's', 'i', 'o', 'n',
        0x03,
    };
    const hashes = try parseTimelineHeadHashes(allocator, minimal);
    defer allocator.free(hashes);
    try std.testing.expectEqual(@as(usize, 0), hashes.len);
}
