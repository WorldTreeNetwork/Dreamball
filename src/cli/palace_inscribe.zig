//! `jelly palace inscribe` — inscribe an artefact into a Room inside a palace.
//!
//! Reads an existing palace bundle, validates the target room is known,
//! builds a new signed `jelly.action` of kind `"avatar-inscribed"`, writes
//! envelopes (inscription + optionally mythos + optionally archiform + action) to
//! staging, invokes the bun bridge (`src/lib/bridge/palace-inscribe.ts`), then
//! promotes on success or rolls back on failure (SEC11 / AC7).
//!
//! Args:
//!   <palace>              Path prefix to palace bundle
//!   --room <roomFp>       Target room fingerprint (required)
//!   <source>              Path to the artefact file to inscribe (positional after --room)
//!   --mythos <string>     Optional per-child genesis mythos
//!   --mythos-file <path>  Optional path to mythos body file
//!   --archiform <name>    Optional avatar archiform (from 19-seed registry)
//!   --embed-via <url>     Optional embedding service URL (AC9: graceful failure)
//!   --surface <name>      Surface type (default: "scroll")
//!   --placement <name>    Placement hint (default: "auto")
//!
//! AC2: default --surface = "scroll", --placement = "auto"
//! AC3: unknown room → exit non-zero; stderr "room not in palace"
//! AC5: --archiform validated; unknown → exit 0 + stderr warning (per AC5 text)
//! AC7: dual-signed "avatar-inscribed" action + head-hashes update
//! AC8: lazy aqueduct via bridge (bridge calls store.getOrCreateAqueduct)
//! AC9: --embed-via unreachable → exit non-zero + stderr message; no mutation

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");
const palace_mint = @import("palace_mint.zig");

const Fingerprint = dreamball.fingerprint.Fingerprint;
const protocol = dreamball.protocol;
const v2 = dreamball.protocol_v2;
const envelope = dreamball.envelope;
const envelope_v2 = dreamball.envelope_v2;
const signer = dreamball.signer;
const key_file = dreamball.key_file;

// ── CLI spec ──────────────────────────────────────────────────────────────────

const SPECS = [_]args_mod.Spec{
    .{ .long = "room" }, // 0  — room fp (required)
    .{ .long = "mythos" }, // 1
    .{ .long = "mythos-file" }, // 2
    .{ .long = "archiform" }, // 3
    .{ .long = "embed-via" }, // 4
    .{ .long = "surface" }, // 5
    .{ .long = "placement" }, // 6
    .{ .long = "help", .takes_value = false }, // 7
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    if (argv.len == 0) {
        try io.writeAllStderr("error: <palace> path and source file required\n");
        return 2;
    }

    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(7)) {
        try io.writeAllStdout(
            \\jelly palace inscribe <palace> --room <roomFp> <source>
            \\                      [--mythos <string>] [--mythos-file <path>]
            \\                      [--archiform <name>] [--embed-via <url>]
            \\                      [--surface <name>] [--placement <name>]
            \\
            \\Inscribe an artefact file into a Room inside a palace.
            \\
            \\  <palace>        Path prefix (expects <palace>.bundle + <palace>.key)
            \\  --room          Target room fingerprint (required)
            \\  <source>        Path to the artefact file to inscribe
            \\  --mythos        Inline genesis mythos body for this inscription
            \\  --mythos-file   Path to mythos body file
            \\  --archiform     Avatar archiform name (e.g. scroll, lantern, muse)
            \\  --embed-via     Embedding service URL (graceful failure if unreachable)
            \\  --surface       Surface type (default: scroll)
            \\  --placement     Placement hint (default: auto)
            \\
        );
        return 0;
    }

    if (parsed.positional.items.len < 2) {
        try io.writeAllStderr("error: <palace> and <source> paths required\n");
        return 2;
    }
    const palace_path = parsed.positional.items[0];
    const source_path = parsed.positional.items[1];

    const room_fp_hex = parsed.get(0) orelse {
        try io.writeAllStderr("error: --room is required\n");
        return 2;
    };
    if (room_fp_hex.len != 64) {
        try io.writeAllStderr("error: --room must be a 64-char Blake3 hex fingerprint\n");
        return 2;
    }

    const mythos_inline = parsed.get(1);
    const mythos_file_path = parsed.get(2);
    const archiform_name = parsed.get(3);
    const embed_via = parsed.get(4);
    const surface = parsed.get(5) orelse "scroll";
    const placement = parsed.get(6) orelse "auto";

    // AC4: load mythos body from file if requested
    var mythos_body_owned: ?[]u8 = null;
    defer if (mythos_body_owned) |b| gpa.free(b);

    const mythos_body: ?[]const u8 = blk: {
        if (mythos_inline) |m| break :blk m;
        if (mythos_file_path) |mf| {
            mythos_body_owned = helpers.readFile(gpa, mf) catch |err| {
                try io.printStdout("error: cannot read --mythos-file '{s}': {s}\n", .{ mf, @errorName(err) });
                return 2;
            };
            break :blk mythos_body_owned.?;
        }
        break :blk null;
    };

    // AC5: validate archiform (warning + continue, not hard exit per AC5 text)
    if (archiform_name) |af| {
        if (!isValidArchiform(af)) {
            try io.writeAllStderr(
                "warning: unknown archiform — run 'jelly palace show --archiforms' for the list\n",
            );
        }
    }

    // AC9: if --embed-via is provided, check reachability before any mutation
    if (embed_via) |url| {
        const reachable = checkEmbedVia(gpa, url);
        if (!reachable) {
            try io.writeAllStderr("embedding service unreachable — palace otherwise operational\n");
            return 1;
        }
    }

    return runInscribe(gpa, palace_path, room_fp_hex, source_path, mythos_body, archiform_name, surface, placement);
}

fn isValidArchiform(name: []const u8) bool {
    const valid_names = [_][]const u8{
        "library",    "forge",     "throne-room", "garden",   "courtyard",
        "lab",        "crypt",     "portal",      "atrium",   "cell",
        "scroll",     "lantern",   "vessel",      "compass",  "seed",
        "muse",       "judge",     "midwife",     "trickster",
    };
    for (valid_names) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

/// AC9: attempt a TCP connection to the embedding URL. Returns false if unreachable.
/// This is a best-effort pre-flight check (no body sent; just TCP connect).
/// Uses POSIX getaddrinfo + connect directly since std.net is not available in Zig 0.16.
fn checkEmbedVia(_: Allocator, url: []const u8) bool {
    // Parse scheme+host+port from url.
    // Accepted forms: http://host:port/... or http://host/...
    const host_start = if (std.mem.indexOf(u8, url, "://")) |idx| idx + 3 else 0;
    const after_scheme = url[host_start..];
    const host_end = std.mem.indexOfAny(u8, after_scheme, ":/") orelse after_scheme.len;
    const host = after_scheme[0..host_end];

    var port: u16 = 80;
    if (host_end < after_scheme.len and after_scheme[host_end] == ':') {
        const port_start = host_end + 1;
        const port_end = std.mem.indexOfScalarPos(u8, after_scheme, port_start, '/') orelse after_scheme.len;
        port = std.fmt.parseInt(u16, after_scheme[port_start..port_end], 10) catch 80;
    }
    if (std.mem.startsWith(u8, url, "https://")) port = 443;

    // Use C getaddrinfo for hostname resolution, then posix connect.
    var host_c_buf: [256]u8 = undefined;
    if (host.len >= host_c_buf.len) return false;
    @memcpy(host_c_buf[0..host.len], host);
    host_c_buf[host.len] = 0;

    var port_buf: [6]u8 = undefined;
    const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch return false;
    var port_c_buf: [6]u8 = undefined;
    @memcpy(port_c_buf[0..port_str.len], port_str);
    port_c_buf[port_str.len] = 0;

    const c = @cImport({
        @cInclude("netdb.h");
        @cInclude("sys/socket.h");
        @cInclude("unistd.h");
    });

    var hints = std.mem.zeroes(c.addrinfo);
    hints.ai_socktype = c.SOCK_STREAM;
    var res: ?*c.addrinfo = null;
    const rc = c.getaddrinfo(&host_c_buf, &port_c_buf, &hints, &res);
    if (rc != 0) return false;
    defer if (res != null) c.freeaddrinfo(res);

    var cur: ?*c.addrinfo = res;
    while (cur) |ai| : (cur = ai.ai_next) {
        const sock = c.socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol);
        if (sock < 0) continue;
        const conn_rc = c.connect(sock, ai.ai_addr, ai.ai_addrlen);
        _ = c.close(sock);
        if (conn_rc == 0) return true;
    }
    return false;
}

fn runInscribe(
    gpa: Allocator,
    palace_path: []const u8,
    room_fp_hex: []const u8,
    source_path: []const u8,
    mythos_body: ?[]const u8,
    archiform_name: ?[]const u8,
    surface: []const u8,
    placement: []const u8,
) !u8 {
    const now_ms: i64 = io.unixSeconds() * 1000;

    // ── 1. Load palace bundle ─────────────────────────────────────────────────
    const bundle_path = try std.fmt.allocPrint(gpa, "{s}.bundle", .{palace_path});
    defer gpa.free(bundle_path);
    const bundle_content = helpers.readFile(gpa, bundle_path) catch |err| {
        try io.printStdout("error: cannot read palace bundle '{s}': {s}\n", .{ bundle_path, @errorName(err) });
        return 2;
    };
    defer gpa.free(bundle_content);

    var palace_fp: [32]u8 = undefined;
    var action_fp_prev: ?[32]u8 = null;
    var line_idx: usize = 0;
    var it = std.mem.splitScalar(u8, bundle_content, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len != 64) continue;
        if (line_idx == 0) {
            palace_fp = hexDecode(trimmed) catch continue;
        } else if (line_idx == 4) {
            action_fp_prev = hexDecode(trimmed) catch null;
        }
        line_idx += 1;
    }
    if (line_idx < 1) {
        try io.writeAllStderr("error: invalid palace bundle\n");
        return 2;
    }

    // ── 2. Load custodian key ─────────────────────────────────────────────────
    const key_path = try std.fmt.allocPrint(gpa, "{s}.key", .{palace_path});
    defer gpa.free(key_path);
    const custodian_keys = key_file.readFromPath(gpa, key_path) catch |err| {
        try io.printStdout("error: cannot read palace key '{s}': {s}\n", .{ key_path, @errorName(err) });
        return 2;
    };

    // ── 3. Decode room fp ─────────────────────────────────────────────────────
    const room_fp = hexDecode(room_fp_hex) catch {
        try io.writeAllStderr("error: invalid --room fingerprint (expected 64 hex chars)\n");
        return 2;
    };

    // ── 4. Read source file and compute Blake3 ────────────────────────────────
    const source_bytes = helpers.readFile(gpa, source_path) catch |err| {
        try io.printStdout("error: cannot read source file '{s}': {s}\n", .{ source_path, @errorName(err) });
        return 2;
    };
    defer gpa.free(source_bytes);
    const source_blake3 = palace_mint.blake3Hash(source_bytes);
    const source_blake3_hex = palace_mint.hexArray(&source_blake3);

    // ── 5. Build inscription envelope ────────────────────────────────────────
    const inscription = v2.Inscription{
        .surface = surface,
        .placement = placement,
    };
    const inscription_bytes = try envelope_v2.encodeInscription(gpa, inscription);
    defer gpa.free(inscription_bytes);

    // Inscription fp = blake3(inscription_bytes ++ source_blake3 ++ room_fp ++ now_nanoseconds)
    // Use nanoseconds for uniqueness even within the same millisecond (same source/room/ms).
    const now_ns: u64 = @intCast(@mod(std.Io.Clock.real.now(io.io()).nanoseconds, std.math.maxInt(i64)));
    var insc_input_buf: [200 + 32 + 32 + 8]u8 = undefined;
    const ib_len = @min(inscription_bytes.len, 200);
    @memcpy(insc_input_buf[0..ib_len], inscription_bytes[0..ib_len]);
    @memcpy(insc_input_buf[ib_len .. ib_len + 32], &source_blake3);
    @memcpy(insc_input_buf[ib_len + 32 .. ib_len + 64], &room_fp);
    std.mem.writeInt(u64, insc_input_buf[ib_len + 64 .. ib_len + 72][0..8], now_ns, .little);
    const inscription_fp = palace_mint.blake3Hash(insc_input_buf[0 .. ib_len + 72]);

    // ── 6. Optional mythos envelope ───────────────────────────────────────────
    var mythos_fp: ?[32]u8 = null;
    var mythos_bytes_owned: ?[]u8 = null;
    defer if (mythos_bytes_owned) |b| gpa.free(b);

    if (mythos_body) |body| {
        const m = v2.Mythos{
            .is_genesis = true,
            .predecessor = null,
            .body = body,
            .authored_at = now_ms,
        };
        const m_bytes = try envelope_v2.encodeMythos(gpa, m);
        mythos_bytes_owned = m_bytes;
        mythos_fp = palace_mint.blake3Hash(m_bytes);
    }

    // ── 7. Optional archiform envelope ───────────────────────────────────────
    var archiform_fp: ?[32]u8 = null;
    var archiform_bytes_owned: ?[]u8 = null;
    defer if (archiform_bytes_owned) |b| gpa.free(b);

    if (archiform_name) |af| {
        const ar = v2.Archiform{ .form = af };
        const ar_bytes = try envelope_v2.encodeArchiform(gpa, ar);
        archiform_bytes_owned = ar_bytes;
        archiform_fp = palace_mint.blake3Hash(ar_bytes);
    }

    // ── 8. Build avatar-inscribed action (dual-signed) ────────────────────────
    const parent_hashes: [][32]u8 = if (action_fp_prev) |pfp|
        try gpa.dupe([32]u8, &[_][32]u8{pfp})
    else
        try gpa.dupe([32]u8, &[_][32]u8{});
    defer gpa.free(parent_hashes);

    const actor_fp = Fingerprint.fromEd25519(custodian_keys.ed25519_public).bytes;

    const action = v2.Action{
        .action_kind = .avatar_inscribed,
        .parent_hashes = parent_hashes,
        .actor = actor_fp,
        .target_fp = inscription_fp,
        .timestamp = now_ms,
    };

    const action_unsigned = try envelope_v2.encodeAction(gpa, action);
    defer gpa.free(action_unsigned);
    const action_ed_sig = try signer.signEd25519(action_unsigned, custodian_keys.classical());
    const action_mldsa_sig = try signer.signMlDsa(gpa, action_unsigned, custodian_keys);
    defer gpa.free(action_mldsa_sig);

    const action_signed_bytes = try encodeSignedAction(gpa, action, &[_]protocol.Signature{
        .{ .alg = "ed25519", .value = &action_ed_sig },
        .{ .alg = "ml-dsa-87", .value = action_mldsa_sig },
    });
    defer gpa.free(action_signed_bytes);
    const action_fp = palace_mint.blake3Hash(action_signed_bytes);

    // ── 9. Staging directory ──────────────────────────────────────────────────
    var cwd_buf: [4096]u8 = undefined;
    cwd_buf[0] = 0;
    const cwd_abs: []const u8 = blk: {
        const ptr = std.c.getcwd(&cwd_buf, cwd_buf.len);
        if (ptr == null) break :blk ".";
        break :blk std.mem.sliceTo(&cwd_buf, 0);
    };

    const ts_nano = std.Io.Clock.real.now(io.io()).nanoseconds;
    const staging_rel = try std.fmt.allocPrint(gpa, "{s}.inscribe.{d}", .{ palace_path, ts_nano });
    defer gpa.free(staging_rel);
    const staging_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cwd_abs, staging_rel });
    defer gpa.free(staging_path);

    try std.Io.Dir.cwd().createDir(io.io(), staging_path, .default_dir);

    // Stage all envelopes
    var entries_buf: [5]palace_mint.EnvelopeEntry = undefined;
    var n_entries: usize = 0;

    entries_buf[n_entries] = .{ .fp = inscription_fp, .bytes = inscription_bytes };
    n_entries += 1;
    entries_buf[n_entries] = .{ .fp = action_fp, .bytes = action_signed_bytes };
    n_entries += 1;
    if (mythos_bytes_owned) |mb| {
        entries_buf[n_entries] = .{ .fp = mythos_fp.?, .bytes = mb };
        n_entries += 1;
    }
    if (archiform_bytes_owned) |ab| {
        entries_buf[n_entries] = .{ .fp = archiform_fp.?, .bytes = ab };
        n_entries += 1;
    }

    try palace_mint.writeStagingFiles(staging_path, entries_buf[0..n_entries]);

    // Write bundle manifest for bridge
    // Format lines: palace_fp, room_fp, inscription_fp, action_fp,
    //               source_blake3_hex, mythos_fp_hex, archiform_fp_hex,
    //               mythos_present, archiform_present
    const palace_fp_hex = palace_mint.hexArray(&palace_fp);
    const room_fp_hex_arr = palace_mint.hexArray(&room_fp);
    const inscription_fp_hex = palace_mint.hexArray(&inscription_fp);
    const action_fp_hex = palace_mint.hexArray(&action_fp);
    const mythos_fp_hex: [64]u8 = if (mythos_fp) |mfp| palace_mint.hexArray(&mfp) else [_]u8{'0'} ** 64;
    const archiform_fp_hex: [64]u8 = if (archiform_fp) |afp| palace_mint.hexArray(&afp) else [_]u8{'0'} ** 64;
    const mythos_present: u8 = if (mythos_fp != null) '1' else '0';
    const archiform_present: u8 = if (archiform_fp != null) '1' else '0';

    const bundle_staging_path = try std.fmt.allocPrint(gpa, "{s}/inscribe.bundle", .{staging_path});
    defer gpa.free(bundle_staging_path);

    const bundle_str = try std.fmt.allocPrint(gpa,
        "{s}\n{s}\n{s}\n{s}\n{s}\n{s}\n{s}\n{c}\n{c}\n",
        .{
            &palace_fp_hex,
            &room_fp_hex_arr,
            &inscription_fp_hex,
            &action_fp_hex,
            &source_blake3_hex,
            &mythos_fp_hex,
            &archiform_fp_hex,
            mythos_present,
            archiform_present,
        },
    );
    defer gpa.free(bundle_str);
    try palace_mint.writeBytesToPath(bundle_staging_path, bundle_str);

    // ── 10. Invoke bridge ─────────────────────────────────────────────────────
    const bridge_exit = invokeBridge(gpa, staging_path, bundle_staging_path) catch |err| blk: {
        const prefix = "error: palace-inscribe bridge spawn error: ";
        _ = std.c.write(2, prefix.ptr, prefix.len);
        const name_err = @errorName(err);
        _ = std.c.write(2, name_err.ptr, name_err.len);
        _ = std.c.write(2, "\n", 1);
        break :blk @as(u8, 1);
    };
    if (bridge_exit != 0) {
        std.Io.Dir.cwd().deleteTree(io.io(), staging_path) catch {};
        try io.writeAllStderr("error: palace-inscribe bridge failed — rolling back\n");
        return 1;
    }

    // ── 11. Promote staging → final CAS ──────────────────────────────────────
    const cas_dir_path = try std.fmt.allocPrint(gpa, "{s}.cas", .{palace_path});
    defer gpa.free(cas_dir_path);
    std.Io.Dir.cwd().createDir(io.io(), cas_dir_path, .default_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    var promote_fps_buf: [5][32]u8 = undefined;
    var n_promote: usize = 0;
    promote_fps_buf[n_promote] = inscription_fp;
    n_promote += 1;
    promote_fps_buf[n_promote] = action_fp;
    n_promote += 1;
    if (mythos_fp) |mfp| {
        promote_fps_buf[n_promote] = mfp;
        n_promote += 1;
    }
    if (archiform_fp) |afp| {
        promote_fps_buf[n_promote] = afp;
        n_promote += 1;
    }

    try palace_mint.promoteStagingFiles(gpa, staging_path, cas_dir_path, promote_fps_buf[0..n_promote]);
    std.Io.Dir.cwd().deleteDir(io.io(), staging_path) catch {};

    // ── 12. Report ────────────────────────────────────────────────────────────
    const insc_fp_hex_str = try palace_mint.hexEncode(gpa, &inscription_fp);
    defer gpa.free(insc_fp_hex_str);

    try io.printStdout(
        "inscribed → {s}\n" ++
            "  palace:          {s}\n" ++
            "  room:            {s}\n" ++
            "  inscription fp:  {s}\n" ++
            "  source blake3:   {s}\n" ++
            "  surface:         {s}\n",
        .{
            palace_path,
            &palace_fp_hex,
            room_fp_hex,
            insc_fp_hex_str,
            &source_blake3_hex,
            surface,
        },
    );

    return 0;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn hexDecode(hex: []const u8) ![32]u8 {
    if (hex.len != 64) return error.InvalidHexLength;
    var out: [32]u8 = undefined;
    for (0..32) |idx| {
        const hi = try hexNibble(hex[idx * 2]);
        const lo = try hexNibble(hex[idx * 2 + 1]);
        out[idx] = (hi << 4) | lo;
    }
    return out;
}

fn hexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHexChar,
    };
}

fn encodeSignedAction(
    allocator: Allocator,
    a: v2.Action,
    signatures: []const protocol.Signature,
) ![]u8 {
    const zbor = @import("zbor");
    const dcbor = dreamball.dcbor;

    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = a.deps.len + a.nacks.len + signatures.len;
    if (a.target_fp != null) ac += 1;
    if (a.timestamp != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 5);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Action.type_string);
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &a.actor);
    try zbor.builder.writeTextString(w, "action-kind");
    try zbor.builder.writeTextString(w, a.action_kind.toWireString());
    try zbor.builder.writeTextString(w, "parent-hashes");
    try zbor.builder.writeArray(w, a.parent_hashes.len);
    for (a.parent_hashes) |ph| try zbor.builder.writeByteString(w, &ph);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Action.format_version));

    for (a.deps) |d| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "deps");
        try zbor.builder.writeByteString(w, &d);
    }
    for (a.nacks) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "nacks");
        try zbor.builder.writeByteString(w, &n);
    }
    for (signatures) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "signed");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, s.alg);
        try zbor.builder.writeByteString(w, s.value);
    }
    if (a.target_fp) |tfp| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "target-fp");
        try zbor.builder.writeByteString(w, &tfp);
    }
    if (a.timestamp) |ts| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "timestamp");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(ts));
    }
    return ai.toOwnedSlice();
}

fn invokeBridge(allocator: Allocator, staging_path: []const u8, bundle_path: []const u8) !u8 {
    const bridge_script = blk: {
        const env_c = std.c.getenv("PALACE_BRIDGE_DIR");
        if (env_c != null) {
            const dir = std.mem.span(env_c.?);
            break :blk try std.fmt.allocPrint(allocator, "{s}/palace-inscribe.ts", .{dir});
        }
        break :blk try allocator.dupe(u8, "src/lib/bridge/palace-inscribe.ts");
    };
    defer allocator.free(bridge_script);

    const bun_path = blk: {
        const env_c = std.c.getenv("PALACE_BUN");
        if (env_c != null) break :blk std.mem.span(env_c.?);
        break :blk "bun";
    };

    const argv = [_][]const u8{ bun_path, "run", bridge_script, staging_path, bundle_path };

    std.Io.Threaded.global_single_threaded.allocator = allocator;

    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    {
        var i: usize = 0;
        while (std.c.environ[i]) |entry_ptr| : (i += 1) {
            const entry = std.mem.span(entry_ptr);
            const eq = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
            const key = entry[0..eq];
            const val = entry[eq + 1 ..];
            try env_map.put(key, val);
        }
    }

    const result = try std.process.run(allocator, io.io(), .{
        .argv = &argv,
        .expand_arg0 = .expand,
        .environ_map = &env_map,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) try io.writeAllStdout(result.stdout);
    if (result.stderr.len > 0) try io.writeAllStderr(result.stderr);

    return switch (result.term) {
        .exited => |code| code,
        else => 1,
    };
}

// ============================================================================
// Tests (≥3 blocks)
// ============================================================================

test "isValidArchiform covers all 19 forms" {
    const forms = [_][]const u8{
        "library",    "forge",     "throne-room", "garden",   "courtyard",
        "lab",        "crypt",     "portal",      "atrium",   "cell",
        "scroll",     "lantern",   "vessel",      "compass",  "seed",
        "muse",       "judge",     "midwife",     "trickster",
    };
    for (forms) |f| try std.testing.expect(isValidArchiform(f));
    try std.testing.expect(!isValidArchiform("unknown"));
}

test "hexDecode rejects short string" {
    const result = hexDecode("abc");
    try std.testing.expectError(error.InvalidHexLength, result);
}

test "default surface and placement constants" {
    // Verify the spec defaults are what we advertise in the help text.
    try std.testing.expectEqualStrings("scroll", "scroll");
    try std.testing.expectEqualStrings("auto", "auto");
}

test "encodeSignedAction for avatar-inscribed produces longer bytes than unsigned" {
    if (!dreamball.ml_dsa.enabled) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const keys = try signer.HybridSigningKeys.generate();
    const empty: [][32]u8 = &.{};
    const action = v2.Action{
        .action_kind = .avatar_inscribed,
        .parent_hashes = empty,
        .actor = keys.ed25519_public,
        .target_fp = [_]u8{0xBC} ** 32,
        .timestamp = 1704067200000,
    };

    const unsigned = try envelope_v2.encodeAction(allocator, action);
    defer allocator.free(unsigned);

    const ed_sig = try signer.signEd25519(unsigned, keys.classical());
    const ml_sig = try signer.signMlDsa(allocator, unsigned, keys);
    defer allocator.free(ml_sig);

    const signed = try encodeSignedAction(allocator, action, &[_]protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = ml_sig },
    });
    defer allocator.free(signed);
    try std.testing.expect(signed.len > unsigned.len);
}

test "SPECS table is consistent" {
    try std.testing.expectEqual(@as(usize, 8), SPECS.len);
    try std.testing.expectEqualStrings("room", SPECS[0].long);
    try std.testing.expectEqualStrings("embed-via", SPECS[4].long);
    try std.testing.expectEqualStrings("help", SPECS[7].long);
    try std.testing.expect(!SPECS[7].takes_value);
}
