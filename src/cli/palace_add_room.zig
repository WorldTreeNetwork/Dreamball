//! `jelly palace add-room` — add a Room to an existing palace DreamBall.
//!
//! Reads an existing palace bundle (resolved via <palace>.bundle + <palace>.key),
//! builds a new signed `jelly.action` of kind `"room-added"`, writes new envelopes
//! (room + optionally mythos + optionally archiform + action) to a staging directory,
//! invokes the bun bridge (`src/lib/bridge/palace-add-room.ts`) which mirrors them
//! into LadybugDB, then promotes on success or rolls back on failure (SEC11 / AC7).
//!
//! Args:
//!   <palace>           Path prefix to palace bundle (expects <palace>.bundle + <palace>.key)
//!   --name <string>    Room name (required)
//!   --mythos <string>  Optional genesis mythos body for this room
//!   --mythos-file <p>  Optional path to mythos body file
//!   --archiform <n>    Optional archiform name; must be in the 19-seed registry (AC3/FR25)
//!
//! AC7: every add-room emits a dual-signed "room-added" action; palace head-hashes updated.
//! AC5: --archiform validates against the registry; unknown → exit non-zero (AC5 says warn, but
//!      the S3.3 spec note at AC5 says "exit 0 + stderr warning". We emit warning + exit 0.
//! AC4: --mythos attaches a jelly.mythos with is-genesis:true; absent → no attribute.
//! AC6: cycle enforcement delegated to the bridge (has graph already loaded).

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

// ── Archiform registry (D-014 — embedded at compile time) ────────────────────
const REGISTRY_BYTES: []const u8 =
    @embedFile("../memory-palace/seed/archiform-registry.json");

// ── CLI spec ──────────────────────────────────────────────────────────────────

const SPECS = [_]args_mod.Spec{
    .{ .long = "name" }, // 0
    .{ .long = "mythos" }, // 1
    .{ .long = "mythos-file" }, // 2
    .{ .long = "archiform" }, // 3
    .{ .long = "help", .takes_value = false }, // 4
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    if (argv.len == 0) {
        try io.writeAllStderr("error: <palace> path required\n");
        return 2;
    }

    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(4)) {
        try io.writeAllStdout(
            \\jelly palace add-room <palace> --name <string>
            \\                      [--mythos <string>] [--mythos-file <path>]
            \\                      [--archiform <name>]
            \\
            \\Add a new Room to an existing palace bundle.
            \\
            \\  <palace>        Path prefix (expects <palace>.bundle + <palace>.key)
            \\  --name          Room name (required)
            \\  --mythos        Inline genesis mythos body for this room
            \\  --mythos-file   Path to mythos body file
            \\  --archiform     Seed archiform name (e.g. library, forge, garden)
            \\
        );
        return 0;
    }

    if (parsed.positional.items.len == 0) {
        try io.writeAllStderr("error: <palace> path required\n");
        return 2;
    }
    const palace_path = parsed.positional.items[0];

    const name = parsed.get(0) orelse {
        try io.writeAllStderr("error: --name is required\n");
        return 2;
    };

    const mythos_inline = parsed.get(1);
    const mythos_file_path = parsed.get(2);
    const archiform_name = parsed.get(3);

    // AC4: if --mythos-file is specified, read it; error if path missing/unreadable
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

    // AC5: validate archiform name against registry
    var archiform_warning: bool = false;
    if (archiform_name) |af| {
        if (!isValidArchiform(af)) {
            try io.writeAllStderr(
                "warning: unknown archiform — run 'jelly palace show --archiforms' for the list\n",
            );
            archiform_warning = true;
        }
    }

    return runAddRoom(gpa, palace_path, name, mythos_body, archiform_name, archiform_warning);
}

/// Validate archiform name against the 19-seed registry (embedded at compile time).
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

fn runAddRoom(
    gpa: Allocator,
    palace_path: []const u8,
    name: []const u8,
    mythos_body: ?[]const u8,
    archiform_name: ?[]const u8,
    archiform_warning: bool,
) !u8 {
    _ = archiform_warning; // warning already emitted; still proceed
    const now_ms: i64 = io.unixSeconds() * 1000;

    // ── 1. Load palace bundle (resolve fps) ──────────────────────────────────
    const bundle_path = try std.fmt.allocPrint(gpa, "{s}.bundle", .{palace_path});
    defer gpa.free(bundle_path);
    const bundle_content = helpers.readFile(gpa, bundle_path) catch |err| {
        try io.printStdout("error: cannot read palace bundle '{s}': {s}\n", .{ bundle_path, @errorName(err) });
        return 2;
    };
    defer gpa.free(bundle_content);

    // Bundle format: one hex fp per line. Line 0 = palace fp.
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
            // Line 4 = current head action fp (per palace-mint bundle order)
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

    // ── 3. Build Room envelope ────────────────────────────────────────────────
    // Genesis hash = blake3(palace_fp ++ name ++ now_ms) — unique seed per room.
    var room_input_buf: [32 + 256 + 8]u8 = undefined;
    const name_len = @min(name.len, 256);
    @memcpy(room_input_buf[0..32], &palace_fp);
    @memcpy(room_input_buf[32 .. 32 + name_len], name[0..name_len]);
    std.mem.writeInt(i64, room_input_buf[32 + name_len .. 32 + name_len + 8][0..8], now_ms, .little);
    const room_genesis_hash = palace_mint.blake3Hash(room_input_buf[0 .. 32 + name_len + 8]);

    // Build room field DreamBall — signed with custodian keys so it can be
    // verified as part of the palace graph.  field_kind="room" lets palace_show
    // and palace_verify detect it as a room envelope.
    var room_db = protocol.DreamBall{
        .stage = .seed,
        .identity = custodian_keys.ed25519_public,
        .identity_pq = custodian_keys.mldsa_public,
        .genesis_hash = room_genesis_hash,
        .revision = 0,
        .dreamball_type = .field,
        .field_kind = "room",
        .name = name,
        .created = now_ms,
    };
    const room_unsigned = try envelope.encodeDreamBall(gpa, room_db);
    defer gpa.free(room_unsigned);
    const room_ed_sig = try signer.signEd25519(room_unsigned, custodian_keys.classical());
    const room_mldsa_sig = try signer.signMlDsa(gpa, room_unsigned, custodian_keys);
    defer gpa.free(room_mldsa_sig);
    const room_sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &room_ed_sig },
        .{ .alg = "ml-dsa-87", .value = room_mldsa_sig },
    };
    room_db.signatures = &room_sigs;
    const room_bytes = try envelope.encodeDreamBall(gpa, room_db);
    defer gpa.free(room_bytes);
    const room_fp = palace_mint.blake3Hash(room_bytes);

    // Encode archiform envelope if provided
    var archiform_fp: ?[32]u8 = null;
    var archiform_bytes_owned: ?[]u8 = null;
    defer if (archiform_bytes_owned) |b| gpa.free(b);

    if (archiform_name) |af| {
        const ar = v2.Archiform{ .form = af };
        const ar_bytes = try envelope_v2.encodeArchiform(gpa, ar);
        archiform_bytes_owned = ar_bytes;
        archiform_fp = palace_mint.blake3Hash(ar_bytes);
    }

    // Encode mythos envelope if provided (AC4)
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

    // ── 4. Build room-added action (dual-signed by custodian) ─────────────────
    const parent_hashes: [][32]u8 = if (action_fp_prev) |pfp|
        try gpa.dupe([32]u8, &[_][32]u8{pfp})
    else
        try gpa.dupe([32]u8, &[_][32]u8{});
    defer gpa.free(parent_hashes);

    const actor_fp = Fingerprint.fromEd25519(custodian_keys.ed25519_public).bytes;

    const action = v2.Action{
        .action_kind = .room_added,
        .parent_hashes = parent_hashes,
        .actor = actor_fp,
        .target_fp = room_fp,
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

    // ── 5. Staging directory ──────────────────────────────────────────────────
    var cwd_buf: [4096]u8 = undefined;
    cwd_buf[0] = 0;
    const cwd_abs: []const u8 = blk: {
        const ptr = std.c.getcwd(&cwd_buf, cwd_buf.len);
        if (ptr == null) break :blk ".";
        break :blk std.mem.sliceTo(&cwd_buf, 0);
    };

    const ts_nano = std.Io.Clock.real.now(io.io()).nanoseconds;
    const staging_rel = try std.fmt.allocPrint(gpa, "{s}.add-room.{d}", .{ palace_path, ts_nano });
    defer gpa.free(staging_rel);
    const staging_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cwd_abs, staging_rel });
    defer gpa.free(staging_path);

    try std.Io.Dir.cwd().createDir(io.io(), staging_path, .default_dir);

    // Collect envelope entries to stage
    var entries_buf: [5]palace_mint.EnvelopeEntry = undefined;
    var n_entries: usize = 0;

    // Room field envelope always staged
    entries_buf[n_entries] = .{ .fp = room_fp, .bytes = room_bytes };
    n_entries += 1;

    // Action envelope always staged
    entries_buf[n_entries] = .{ .fp = action_fp, .bytes = action_signed_bytes };
    n_entries += 1;

    // Mythos envelope if provided
    if (mythos_bytes_owned) |mb| {
        entries_buf[n_entries] = .{ .fp = mythos_fp.?, .bytes = mb };
        n_entries += 1;
    }

    // Archiform envelope if provided
    if (archiform_bytes_owned) |ab| {
        entries_buf[n_entries] = .{ .fp = archiform_fp.?, .bytes = ab };
        n_entries += 1;
    }

    try palace_mint.writeStagingFiles(staging_path, entries_buf[0..n_entries]);

    // Write bundle manifest for bridge: palace_fp, room_fp, action_fp + optional fps
    var bundle_fps_buf: [4][32]u8 = undefined;
    var n_fps: usize = 0;
    bundle_fps_buf[n_fps] = palace_fp;
    n_fps += 1;
    bundle_fps_buf[n_fps] = room_fp;
    n_fps += 1;
    bundle_fps_buf[n_fps] = action_fp;
    n_fps += 1;

    // Append optional fps as hex lines in bundle (bridge reads by index)
    // Format: palace_fp, room_fp, action_fp, [mythos_fp|""], [archiform_fp|""], name_b64
    const bundle_staging_path = try std.fmt.allocPrint(gpa, "{s}/add-room.bundle", .{staging_path});
    defer gpa.free(bundle_staging_path);

    const palace_fp_hex = palace_mint.hexArray(&palace_fp);
    const room_fp_hex = palace_mint.hexArray(&room_fp);
    const action_fp_hex_arr = palace_mint.hexArray(&action_fp);
    const mythos_fp_hex: [64]u8 = if (mythos_fp) |mfp| palace_mint.hexArray(&mfp) else [_]u8{'0'} ** 64;
    const archiform_fp_hex: [64]u8 = if (archiform_fp) |afp| palace_mint.hexArray(&afp) else [_]u8{'0'} ** 64;
    const mythos_present: u8 = if (mythos_fp != null) '1' else '0';
    const archiform_present: u8 = if (archiform_fp != null) '1' else '0';

    const bundle_str = try std.fmt.allocPrint(gpa,
        "{s}\n{s}\n{s}\n{s}\n{s}\n{c}\n{c}\n{s}\n",
        .{
            &palace_fp_hex,
            &room_fp_hex,
            &action_fp_hex_arr,
            &mythos_fp_hex,
            &archiform_fp_hex,
            mythos_present,
            archiform_present,
            name,
        },
    );
    defer gpa.free(bundle_str);
    try palace_mint.writeBytesToPath(bundle_staging_path, bundle_str);

    // ── 6. Invoke bridge ──────────────────────────────────────────────────────
    const bridge_exit = invokeBridge(gpa, staging_path, bundle_staging_path) catch |err| blk: {
        const prefix = "error: palace-add-room bridge spawn error: ";
        _ = std.c.write(2, prefix.ptr, prefix.len);
        const name_err = @errorName(err);
        _ = std.c.write(2, name_err.ptr, name_err.len);
        _ = std.c.write(2, "\n", 1);
        break :blk @as(u8, 1);
    };
    if (bridge_exit != 0) {
        std.Io.Dir.cwd().deleteTree(io.io(), staging_path) catch {};
        try io.writeAllStderr("error: palace-add-room bridge failed — rolling back\n");
        return 1;
    }

    // ── 7. Promote staging → final CAS (SEC11 atomic rename) ─────────────────
    const cas_dir_path = try std.fmt.allocPrint(gpa, "{s}.cas", .{palace_path});
    defer gpa.free(cas_dir_path);
    std.Io.Dir.cwd().createDir(io.io(), cas_dir_path, .default_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    // Promote all staged envelopes (room + action + optional mythos + optional archiform)
    var promote_fps_buf: [5][32]u8 = undefined;
    var n_promote: usize = 0;
    promote_fps_buf[n_promote] = room_fp;
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

    // Clean up staging dir
    std.Io.Dir.cwd().deleteDir(io.io(), staging_path) catch {};

    // ── 7b. Append new fps to palace bundle ───────────────────────────────────
    // The palace bundle is the canonical ordered list of all envelope fps for this
    // palace.  After a successful add-room we append: room_fp, action_fp (and
    // optional mythos/archiform fps) so `palace verify` and `palace show` can find
    // all envelopes by scanning the bundle.
    {
        const room_fp_hex_append = palace_mint.hexArray(&room_fp);
        // Build append string: room_fp + action_fp + optional fps
        var lines_buf: std.ArrayList(u8) = .empty;
        defer lines_buf.deinit(gpa);
        try lines_buf.appendSlice(gpa, &room_fp_hex_append);
        try lines_buf.append(gpa, '\n');
        try lines_buf.appendSlice(gpa, &action_fp_hex_arr);
        try lines_buf.append(gpa, '\n');
        if (mythos_fp) |mfp| {
            const mhex = palace_mint.hexArray(&mfp);
            try lines_buf.appendSlice(gpa, &mhex);
            try lines_buf.append(gpa, '\n');
        }
        if (archiform_fp) |afp| {
            const ahex = palace_mint.hexArray(&afp);
            try lines_buf.appendSlice(gpa, &ahex);
            try lines_buf.append(gpa, '\n');
        }
        // Append to the existing palace bundle file: concatenate existing + new fps
        var combined: std.ArrayList(u8) = .empty;
        defer combined.deinit(gpa);
        try combined.appendSlice(gpa, bundle_content);
        try combined.appendSlice(gpa, lines_buf.items);
        try palace_mint.writeBytesToPath(bundle_path, combined.items);
    }

    // ── 8. Report ─────────────────────────────────────────────────────────────
    const room_fp_hex_report = try palace_mint.hexEncode(gpa, &room_fp);
    defer gpa.free(room_fp_hex_report);

    try io.printStdout(
        "added room → {s}\n" ++
            "  palace:     {s}\n" ++
            "  room fp:    {s}\n" ++
            "  name:       {s}\n",
        .{
            palace_path,
            &palace_fp_hex,
            room_fp_hex_report,
            name,
        },
    );

    return 0;
}

// ── Helpers (re-used from palace_mint.zig pattern) ────────────────────────────

fn hexDecode(hex: []const u8) ![32]u8 {
    if (hex.len != 64) return error.InvalidHexLength;
    var out: [32]u8 = undefined;
    for (0..32) |i| {
        const hi = try hexNibble(hex[i * 2]);
        const lo = try hexNibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
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
            break :blk try std.fmt.allocPrint(allocator, "{s}/palace-add-room.ts", .{dir});
        }
        break :blk try allocator.dupe(u8, "src/lib/bridge/palace-add-room.ts");
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
// Tests (AC8 — ≥3 test blocks)
// ============================================================================

test "isValidArchiform accepts all 19 seed forms" {
    const valid = [_][]const u8{
        "library",    "forge",     "throne-room", "garden",   "courtyard",
        "lab",        "crypt",     "portal",      "atrium",   "cell",
        "scroll",     "lantern",   "vessel",      "compass",  "seed",
        "muse",       "judge",     "midwife",     "trickster",
    };
    for (valid) |name| {
        try std.testing.expect(isValidArchiform(name));
    }
}

test "isValidArchiform rejects unknown name" {
    try std.testing.expect(!isValidArchiform("frobnicator"));
    try std.testing.expect(!isValidArchiform(""));
    try std.testing.expect(!isValidArchiform("LIBRARY")); // case-sensitive
}

test "hexDecode round-trips for known bytes" {
    const input = [_]u8{0xde} ** 32;
    const hex = palace_mint.hexArray(&input);
    const decoded = try hexDecode(&hex);
    try std.testing.expectEqualSlices(u8, &input, &decoded);
}

test "encodeSignedAction for room-added produces longer bytes than unsigned" {
    if (!dreamball.ml_dsa.enabled) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const keys = try signer.HybridSigningKeys.generate();
    const empty: [][32]u8 = &.{};
    const action = v2.Action{
        .action_kind = .room_added,
        .parent_hashes = empty,
        .actor = keys.ed25519_public,
        .target_fp = [_]u8{0xAB} ** 32,
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
    try std.testing.expectEqual(@as(usize, 5), SPECS.len);
    try std.testing.expectEqualStrings("name", SPECS[0].long);
    try std.testing.expectEqualStrings("mythos", SPECS[1].long);
    try std.testing.expectEqualStrings("mythos-file", SPECS[2].long);
    try std.testing.expectEqualStrings("archiform", SPECS[3].long);
    try std.testing.expectEqualStrings("help", SPECS[4].long);
    try std.testing.expect(!SPECS[4].takes_value);
}
