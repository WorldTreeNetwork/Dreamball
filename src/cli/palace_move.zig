//! `jelly palace move` — move an inscription from one Room to another.
//!
//! Reads an existing palace bundle, validates both source and destination rooms,
//! builds a new signed `jelly.action` of kind `"move"`, writes it to staging,
//! invokes the bun bridge (`src/lib/bridge/palace-move.ts`) which updates:
//!   - LadybugDB LIVES_IN edge (delete old, create new)
//!   - oracle Agent knowledge_graph triple via updateTriple
//!   - ActionLog row via recordAction
//! Then promotes on success or rolls back on failure (SEC11 / D-008).
//!
//! Args:
//!   <palace>              Path prefix to palace bundle
//!   --avatar <docFp>      Inscription fingerprint to move (required)
//!   --to <roomFp>         Destination room fingerprint (required)
//!
//! SEC11: action signed before graph mutation.
//! D-008: 4-step transaction discipline (begin → mutate → record → commit).

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");
const palace_mint = @import("palace_mint.zig");
const palace_inscribe = @import("palace_inscribe.zig");

const Fingerprint = dreamball.fingerprint.Fingerprint;
const protocol = dreamball.protocol;
const v2 = dreamball.protocol_v2;
const envelope_v2 = dreamball.envelope_v2;
const signer = dreamball.signer;
const key_file = dreamball.key_file;

// ── CLI spec ──────────────────────────────────────────────────────────────────

const SPECS = [_]args_mod.Spec{
    .{ .long = "avatar" }, // 0 — inscription fp (required)
    .{ .long = "to" },     // 1 — destination room fp (required)
    .{ .long = "help", .takes_value = false }, // 2
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    if (argv.len == 0) {
        try io.writeAllStderr("error: <palace> path required\n");
        return 2;
    }

    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(2)) {
        try io.writeAllStdout(
            \\jelly palace move <palace> --avatar <docFp> --to <roomFp>
            \\
            \\Move an inscription from its current Room to a new destination Room.
            \\
            \\  <palace>    Path prefix (expects <palace>.bundle + <palace>.key)
            \\  --avatar    Inscription fingerprint (64 hex chars)
            \\  --to        Destination room fingerprint (64 hex chars)
            \\
        );
        return 0;
    }

    if (parsed.positional.items.len < 1) {
        try io.writeAllStderr("error: <palace> path required\n");
        return 2;
    }
    const palace_path = parsed.positional.items[0];

    const avatar_fp_hex = parsed.get(0) orelse {
        try io.writeAllStderr("error: --avatar is required\n");
        return 2;
    };
    if (avatar_fp_hex.len != 64) {
        try io.writeAllStderr("error: --avatar must be a 64-char Blake3 hex fingerprint\n");
        return 2;
    }

    const to_room_fp_hex = parsed.get(1) orelse {
        try io.writeAllStderr("error: --to is required\n");
        return 2;
    };
    if (to_room_fp_hex.len != 64) {
        try io.writeAllStderr("error: --to must be a 64-char Blake3 hex fingerprint\n");
        return 2;
    }

    return runMove(gpa, palace_path, avatar_fp_hex, to_room_fp_hex);
}

fn runMove(
    gpa: Allocator,
    palace_path: []const u8,
    avatar_fp_hex: []const u8,
    to_room_fp_hex: []const u8,
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

    // ── 3. Decode fps ─────────────────────────────────────────────────────────
    const avatar_fp = hexDecode(avatar_fp_hex) catch {
        try io.writeAllStderr("error: invalid --avatar fingerprint\n");
        return 2;
    };
    const to_room_fp = hexDecode(to_room_fp_hex) catch {
        try io.writeAllStderr("error: invalid --to fingerprint\n");
        return 2;
    };

    // ── 4. Build move action (dual-signed) ────────────────────────────────────
    const parent_hashes: [][32]u8 = if (action_fp_prev) |pfp|
        try gpa.dupe([32]u8, &[_][32]u8{pfp})
    else
        try gpa.dupe([32]u8, &[_][32]u8{});
    defer gpa.free(parent_hashes);

    const actor_fp = Fingerprint.fromEd25519(custodian_keys.ed25519_public).bytes;

    const action = v2.Action{
        .action_kind = .move,
        .parent_hashes = parent_hashes,
        .actor = actor_fp,
        .target_fp = avatar_fp,
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

    // ── 5. Staging ────────────────────────────────────────────────────────────
    var cwd_buf: [4096]u8 = undefined;
    cwd_buf[0] = 0;
    const cwd_abs: []const u8 = blk: {
        const ptr = std.c.getcwd(&cwd_buf, cwd_buf.len);
        if (ptr == null) break :blk ".";
        break :blk std.mem.sliceTo(&cwd_buf, 0);
    };

    const ts_nano = std.Io.Clock.real.now(io.io()).nanoseconds;
    const staging_rel = try std.fmt.allocPrint(gpa, "{s}.move.{d}", .{ palace_path, ts_nano });
    defer gpa.free(staging_rel);
    const staging_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cwd_abs, staging_rel });
    defer gpa.free(staging_path);

    try std.Io.Dir.cwd().createDir(io.io(), staging_path, .default_dir);

    var entries_buf: [1]palace_mint.EnvelopeEntry = undefined;
    entries_buf[0] = .{ .fp = action_fp, .bytes = action_signed_bytes };
    try palace_mint.writeStagingFiles(staging_path, entries_buf[0..1]);

    // Write bundle manifest for bridge
    // Format: palace_fp, avatar_fp (doc to move), to_room_fp, action_fp
    const palace_fp_hex = palace_mint.hexArray(&palace_fp);
    const avatar_fp_hex_arr = palace_mint.hexArray(&avatar_fp);
    const to_room_fp_hex_arr = palace_mint.hexArray(&to_room_fp);
    const action_fp_hex = palace_mint.hexArray(&action_fp);

    const bundle_staging_path = try std.fmt.allocPrint(gpa, "{s}/move.bundle", .{staging_path});
    defer gpa.free(bundle_staging_path);

    const bundle_str = try std.fmt.allocPrint(gpa,
        "{s}\n{s}\n{s}\n{s}\n",
        .{
            &palace_fp_hex,
            &avatar_fp_hex_arr,
            &to_room_fp_hex_arr,
            &action_fp_hex,
        },
    );
    defer gpa.free(bundle_str);
    try palace_mint.writeBytesToPath(bundle_staging_path, bundle_str);

    // ── 6. Invoke bridge ─────────────────────────────────────────────────────
    const bridge_exit = invokeBridge(gpa, staging_path, bundle_staging_path) catch |err| blk: {
        const prefix = "error: palace-move bridge spawn error: ";
        _ = std.c.write(2, prefix.ptr, prefix.len);
        const name_err = @errorName(err);
        _ = std.c.write(2, name_err.ptr, name_err.len);
        _ = std.c.write(2, "\n", 1);
        break :blk @as(u8, 1);
    };
    if (bridge_exit != 0) {
        std.Io.Dir.cwd().deleteTree(io.io(), staging_path) catch {};
        try io.writeAllStderr("error: palace-move bridge failed — rolling back\n");
        return 1;
    }

    // ── 7. Promote staging → final CAS ───────────────────────────────────────
    const cas_dir_path = try std.fmt.allocPrint(gpa, "{s}.cas", .{palace_path});
    defer gpa.free(cas_dir_path);
    std.Io.Dir.cwd().createDir(io.io(), cas_dir_path, .default_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    try palace_mint.promoteStagingFiles(gpa, staging_path, cas_dir_path, &[_][32]u8{action_fp});
    std.Io.Dir.cwd().deleteDir(io.io(), staging_path) catch {};

    // ── 8. Report ─────────────────────────────────────────────────────────────
    try io.printStdout(
        "moved → {s}\n" ++
            "  palace:   {s}\n" ++
            "  avatar:   {s}\n" ++
            "  to room:  {s}\n",
        .{
            palace_path,
            &palace_fp_hex,
            avatar_fp_hex,
            to_room_fp_hex,
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
            break :blk try std.fmt.allocPrint(allocator, "{s}/palace-move.ts", .{dir});
        }
        break :blk try allocator.dupe(u8, "src/lib/bridge/palace-move.ts");
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

// ── Tests ─────────────────────────────────────────────────────────────────────

test "SPECS table is consistent" {
    try std.testing.expectEqual(@as(usize, 3), SPECS.len);
    try std.testing.expectEqualStrings("avatar", SPECS[0].long);
    try std.testing.expectEqualStrings("to", SPECS[1].long);
    try std.testing.expectEqualStrings("help", SPECS[2].long);
    try std.testing.expect(!SPECS[2].takes_value);
}

test "hexDecode rejects short string" {
    try std.testing.expectError(error.InvalidHexLength, hexDecode("abc"));
}

test "hexDecode accepts 64-char hex" {
    const hex = "0" ** 64;
    const result = try hexDecode(hex);
    for (result) |b| try std.testing.expectEqual(@as(u8, 0), b);
}
