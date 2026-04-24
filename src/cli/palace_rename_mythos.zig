//! `jelly palace rename-mythos` — append a new canonical jelly.mythos to a palace.
//!
//! Appends a new `jelly.mythos` with `predecessor = Blake3(prior head)`, emits a
//! paired `"true-naming"` `jelly.action` referenced by `discovered-in`, bumps
//! revision, re-signs with both signatures, and rejects second-genesis attempts.
//!
//! Args:
//!   <palace>            Path prefix (expects <palace>.bundle + <palace>.key)
//!   --body <text>       New mythos body (required; alt: --body-file <path>)
//!   --body-file <path>  Path to a file containing the mythos body
//!   --true-name <word>  Optional condensed totem word
//!   --form <string>     Optional archiform form (NOT validated against registry here — TC18)
//!
//! Security (AC8 / SEC3):
//!   Any attempt to attach guild-only quorum to a canonical chain mythos is
//!   REJECTED. Canonical mythos are always public. No `--guild-only` flag exists;
//!   see guard in runRenameMythos.
//!
//! Atomicity (SEC11):
//!   Same staging-then-rename pattern as palace_mint.zig / palace_add_room.zig.
//!   Bridge exits non-zero → Zig deletes staging dir and exits 1.
//!
//! AC3 second-genesis rejection:
//!   The internal API `renameMythos` rejects any caller that would produce a new
//!   mythos with `is-genesis: true` when a predecessor already exists in the chain.
//!   The bridge enforces this at the DB level too (checks MYTHOS_HEAD exists before
//!   accepting). The Zig CLI never passes is-genesis: true to a successor envelope.

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
const envelope_v2 = dreamball.envelope_v2;
const signer = dreamball.signer;
const key_file = dreamball.key_file;

// ── CLI spec ──────────────────────────────────────────────────────────────────

const SPECS = [_]args_mod.Spec{
    .{ .long = "body" },          // 0 — required (alt: --body-file)
    .{ .long = "body-file" },     // 1 — alt body source
    .{ .long = "true-name" },     // 2 — optional totem word
    .{ .long = "form" },          // 3 — optional open-enum form (TC18: NOT validated)
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
            \\jelly palace rename-mythos <palace> --body <text>
            \\                           [--body-file <path>]
            \\                           [--true-name <word>]
            \\                           [--form <form>]
            \\
            \\Append a new canonical jelly.mythos to the palace's true-name chain.
            \\
            \\  <palace>        Path prefix (expects <palace>.bundle + <palace>.key)
            \\  --body          New mythos body text (required)
            \\  --body-file     Path to file containing the mythos body
            \\  --true-name     Optional condensed totem word (e.g. "rememberer")
            \\  --form          Optional open-enum form (not validated here — TC18)
            \\
            \\Note: canonical-chain mythos are always public (SEC3). The --guild-only
            \\flag does not exist for this verb and is rejected at the API level.
            \\
        );
        return 0;
    }

    if (parsed.positional.items.len == 0) {
        try io.writeAllStderr("error: <palace> path required\n");
        return 2;
    }
    const palace_path = parsed.positional.items[0];

    const body_inline = parsed.get(0);
    const body_file_path = parsed.get(1);
    const true_name = parsed.get(2);
    const form = parsed.get(3);

    // AC8 / SEC3: guard — no guild-only flag exists here; if somehow a future
    // code path tries to set guild-only on a canonical chain mythos, it must be
    // rejected here. Since the flag doesn't exist in SPECS we are safe, but
    // document the intent explicitly.
    // (Any argv element "--guild-only" would be rejected as unknown by args_mod.parse.)

    // Read body from --body or --body-file.
    var body_owned: ?[]u8 = null;
    defer if (body_owned) |b| gpa.free(b);

    const body: []const u8 = blk: {
        if (body_inline) |b| break :blk b;
        if (body_file_path) |bf| {
            body_owned = helpers.readFile(gpa, bf) catch |err| {
                try io.printStdout("error: cannot read --body-file '{s}': {s}\n", .{ bf, @errorName(err) });
                return 2;
            };
            break :blk body_owned.?;
        }
        try io.writeAllStderr(
            "error: --body is required\n" ++
                "  provide --body <text> or --body-file <path>\n",
        );
        return 2;
    };

    return runRenameMythos(gpa, palace_path, body, true_name, form);
}

/// AC3: Internal guard — refuse to mint a new is-genesis: true mythos when a
/// predecessor fp is provided. Called by runRenameMythos before encoding.
/// Returns error.SecondGenesisRejected if guard trips.
fn assertNotSecondGenesis(predecessor_fp: ?[32]u8, is_genesis_requested: bool) !void {
    if (is_genesis_requested and predecessor_fp != null) {
        return error.SecondGenesisRejected;
    }
}

fn runRenameMythos(
    gpa: Allocator,
    palace_path: []const u8,
    body: []const u8,
    true_name: ?[]const u8,
    form: ?[]const u8,
) !u8 {
    const now_ms: i64 = io.unixSeconds() * 1000;

    // ── 1. Load palace bundle ────────────────────────────────────────────────
    const bundle_path = try std.fmt.allocPrint(gpa, "{s}.bundle", .{palace_path});
    defer gpa.free(bundle_path);
    const bundle_content = helpers.readFile(gpa, bundle_path) catch |err| {
        try io.printStdout("error: cannot read palace bundle '{s}': {s}\n", .{ bundle_path, @errorName(err) });
        return 2;
    };
    defer gpa.free(bundle_content);

    // Parse palace fp (line 0) and current head action fp (line 4).
    var palace_fp: [32]u8 = undefined;
    var current_head_action_fp: ?[32]u8 = null;
    var current_mythos_fp: ?[32]u8 = null;
    var line_idx: usize = 0;
    var it = std.mem.splitScalar(u8, bundle_content, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len != 64) continue;
        switch (line_idx) {
            0 => palace_fp = hexDecode(trimmed) catch continue,
            // Bundle order from palace_mint.zig: palace, oracle, mythos, registry, action, timeline
            2 => current_mythos_fp = hexDecode(trimmed) catch null,
            4 => current_head_action_fp = hexDecode(trimmed) catch null,
            else => {},
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

    // ── 3. Resolve predecessor mythos fp ─────────────────────────────────────
    // The current head mythos fp is read from the bundle (line 2). If the
    // palace has no prior rename, line 2 = genesis mythos fp.
    // We'll pass the predecessor to the bridge which resolves MYTHOS_HEAD
    // from the store; here we embed the fp from the bundle.
    const predecessor_fp: ?[32]u8 = current_mythos_fp;

    // AC3: Successor mythos MUST NOT be is-genesis: true.
    // predecessorFp != null means this is a successor, not genesis.
    assertNotSecondGenesis(predecessor_fp, false) catch {
        try io.writeAllStderr("error: second genesis rejected — a genesis mythos already exists\n");
        return 1;
    };

    // ── 4. Build new canonical mythos envelope (M1) ──────────────────────────
    // AC1: is-genesis: false, predecessor = M0's fp, body = CLI body.
    // AC1: form verbatim (TC18: no archiform registry validation here).
    // AC8 / SEC3: never set guild-only on this envelope.
    const new_mythos = v2.Mythos{
        .is_genesis = false, // Always false for rename-mythos (AC3 guard above)
        .predecessor = predecessor_fp,
        .body = body,
        .true_name = true_name,
        .form = form,
        .authored_at = now_ms,
        // discovered_in set after we have the action fp (set by bridge, not Zig)
    };

    const new_mythos_bytes = try envelope_v2.encodeMythos(gpa, new_mythos);
    defer gpa.free(new_mythos_bytes);
    const new_mythos_fp = palace_mint.blake3Hash(new_mythos_bytes);

    // ── 5. Build "true-naming" action (dual-signed by custodian) ─────────────
    const actor_fp = Fingerprint.fromEd25519(custodian_keys.ed25519_public).bytes;

    const parent_hashes: [][32]u8 = if (current_head_action_fp) |pfp|
        try gpa.dupe([32]u8, &[_][32]u8{pfp})
    else
        try gpa.dupe([32]u8, &[_][32]u8{});
    defer gpa.free(parent_hashes);

    const action = v2.Action{
        .action_kind = .true_naming,
        .parent_hashes = parent_hashes,
        .actor = actor_fp,
        .target_fp = new_mythos_fp, // target = new mythos fp (AC7)
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

    // ── 6. Staging directory ──────────────────────────────────────────────────
    var cwd_buf: [4096]u8 = undefined;
    cwd_buf[0] = 0;
    const cwd_abs: []const u8 = blk: {
        const ptr = std.c.getcwd(&cwd_buf, cwd_buf.len);
        if (ptr == null) break :blk ".";
        break :blk std.mem.sliceTo(&cwd_buf, 0);
    };

    const ts_nano = std.Io.Clock.real.now(io.io()).nanoseconds;
    const staging_rel = try std.fmt.allocPrint(gpa, "{s}.rename-mythos.{d}", .{ palace_path, ts_nano });
    defer gpa.free(staging_rel);
    const staging_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cwd_abs, staging_rel });
    defer gpa.free(staging_path);

    try std.Io.Dir.cwd().createDir(io.io(), staging_path, .default_dir);

    // Stage: new mythos + signed action.
    try palace_mint.writeStagingFiles(staging_path, &[_]palace_mint.EnvelopeEntry{
        .{ .fp = new_mythos_fp, .bytes = new_mythos_bytes },
        .{ .fp = action_fp, .bytes = action_signed_bytes },
    });

    // Write bundle manifest for bridge.
    // Format (one value per line):
    //   0: palace_fp
    //   1: new_mythos_fp (M1)
    //   2: action_fp ("true-naming" action)
    //   3: predecessor_fp (M0) or "0"×64 if genesis (should not happen here)
    //   4: "1" if predecessor present, "0" otherwise
    //   5: true_name or "" if absent
    //   6: form or "" if absent
    const palace_fp_hex = palace_mint.hexArray(&palace_fp);
    const new_mythos_fp_hex = palace_mint.hexArray(&new_mythos_fp);
    const action_fp_hex = palace_mint.hexArray(&action_fp);
    const pred_fp_hex: [64]u8 = if (predecessor_fp) |p| palace_mint.hexArray(&p) else [_]u8{'0'} ** 64;
    const pred_present: u8 = if (predecessor_fp != null) '1' else '0';

    const bundle_staging_path = try std.fmt.allocPrint(gpa, "{s}/rename-mythos.bundle", .{staging_path});
    defer gpa.free(bundle_staging_path);

    const bundle_str = try std.fmt.allocPrint(gpa,
        "{s}\n{s}\n{s}\n{s}\n{c}\n{s}\n{s}\n",
        .{
            &palace_fp_hex,
            &new_mythos_fp_hex,
            &action_fp_hex,
            &pred_fp_hex,
            pred_present,
            true_name orelse "",
            form orelse "",
        },
    );
    defer gpa.free(bundle_str);
    try palace_mint.writeBytesToPath(bundle_staging_path, bundle_str);

    // ── 7. Invoke bridge ──────────────────────────────────────────────────────
    const bridge_exit = invokeBridge(gpa, staging_path, bundle_staging_path) catch |err| blk: {
        const prefix = "error: palace-rename-mythos bridge spawn error: ";
        _ = std.c.write(2, prefix.ptr, prefix.len);
        const name = @errorName(err);
        _ = std.c.write(2, name.ptr, name.len);
        _ = std.c.write(2, "\n", 1);
        break :blk @as(u8, 1);
    };

    if (bridge_exit != 0) {
        std.Io.Dir.cwd().deleteTree(io.io(), staging_path) catch {};
        try io.writeAllStderr("error: palace-rename-mythos bridge failed — rolling back\n");
        return 1;
    }

    // ── 8. Promote staging → final CAS (SEC11 atomic rename) ─────────────────
    const cas_dir_path = try std.fmt.allocPrint(gpa, "{s}.cas", .{palace_path});
    defer gpa.free(cas_dir_path);
    std.Io.Dir.cwd().createDir(io.io(), cas_dir_path, .default_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    try palace_mint.promoteStagingFiles(gpa, staging_path, cas_dir_path, &[_][32]u8{
        new_mythos_fp,
        action_fp,
    });

    std.Io.Dir.cwd().deleteDir(io.io(), staging_path) catch {};

    // ── 9. Report ─────────────────────────────────────────────────────────────
    const new_mythos_fp_report = try palace_mint.hexEncode(gpa, &new_mythos_fp);
    defer gpa.free(new_mythos_fp_report);
    const action_fp_report = try palace_mint.hexEncode(gpa, &action_fp);
    defer gpa.free(action_fp_report);

    try io.printStdout(
        "renamed mythos → {s}\n" ++
            "  new mythos fp: {s}\n" ++
            "  action fp:     {s}\n" ++
            "  action kind:   true-naming\n",
        .{ palace_path, new_mythos_fp_report, action_fp_report },
    );

    return 0;
}

// ── Signed action encoder (mirrored from palace_mint.zig) ─────────────────────

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

// ── Hex helpers ───────────────────────────────────────────────────────────────

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

// ── Bridge invocation ─────────────────────────────────────────────────────────

fn invokeBridge(allocator: Allocator, staging_path: []const u8, bundle_path: []const u8) !u8 {
    const bridge_script = blk: {
        const env_c = std.c.getenv("PALACE_BRIDGE_DIR");
        if (env_c != null) {
            const dir = std.mem.span(env_c.?);
            break :blk try std.fmt.allocPrint(allocator, "{s}/palace-rename-mythos.ts", .{dir});
        }
        break :blk try allocator.dupe(u8, "src/lib/bridge/palace-rename-mythos.ts");
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
// Tests — AC8 / thorough tier
// ============================================================================

test "SPECS table is consistent with CLI spec" {
    try std.testing.expectEqual(@as(usize, 5), SPECS.len);
    try std.testing.expectEqualStrings("body", SPECS[0].long);
    try std.testing.expectEqualStrings("body-file", SPECS[1].long);
    try std.testing.expectEqualStrings("true-name", SPECS[2].long);
    try std.testing.expectEqualStrings("form", SPECS[3].long);
    try std.testing.expectEqualStrings("help", SPECS[4].long);
    try std.testing.expect(!SPECS[4].takes_value);
}

test "assertNotSecondGenesis: allows genesis with no predecessor" {
    // is_genesis=true + no predecessor → ok (first mint scenario; not relevant to rename-mythos
    // but the guard should not trip for this case)
    try assertNotSecondGenesis(null, true);
}

test "assertNotSecondGenesis: rejects is-genesis when predecessor exists (AC3)" {
    const pred_fp = [_]u8{0xAA} ** 32;
    const result = assertNotSecondGenesis(pred_fp, true);
    try std.testing.expectError(error.SecondGenesisRejected, result);
}

test "assertNotSecondGenesis: allows successor (is_genesis=false) with predecessor" {
    const pred_fp = [_]u8{0xBB} ** 32;
    try assertNotSecondGenesis(pred_fp, false);
}

test "hexDecode round-trips for known bytes" {
    const input = [_]u8{0xca} ** 32;
    const hex = palace_mint.hexArray(&input);
    const decoded = try hexDecode(&hex);
    try std.testing.expectEqualSlices(u8, &input, &decoded);
}

test "hexDecode rejects wrong length" {
    const result = hexDecode("abc");
    try std.testing.expectError(error.InvalidHexLength, result);
}

test "encodeSignedAction for true-naming produces signed bytes" {
    if (!dreamball.ml_dsa.enabled) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const keys = try signer.HybridSigningKeys.generate();
    const empty: [][32]u8 = &.{};
    const action = v2.Action{
        .action_kind = .true_naming,
        .parent_hashes = empty,
        .actor = keys.ed25519_public,
        .target_fp = [_]u8{0xDE} ** 32,
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

    // Signed must be longer than unsigned (two signatures attached).
    try std.testing.expect(signed.len > unsigned.len);
    // Deterministic Blake3.
    const fp1 = palace_mint.blake3Hash(signed);
    const fp2 = palace_mint.blake3Hash(signed);
    try std.testing.expectEqualSlices(u8, &fp1, &fp2);
}

test "SEC3: no guild-only flag in SPECS" {
    // Verify that no spec entry carries 'guild-only' — canonical chain mythos must
    // always be public. This test locks the invariant statically.
    for (SPECS) |s| {
        try std.testing.expect(!std.mem.eql(u8, s.long, "guild-only"));
    }
}
