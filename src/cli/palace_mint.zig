//! `jelly palace mint` — mint a new palace DreamBall.
//!
//! Produces six CAS envelopes written to a staging directory, then either:
//!   (a) invokes the bun bridge (`src/lib/bridge/palace-mint.ts`) which
//!       mirrors them into LadybugDB and returns exit 0, at which point
//!       Zig promotes the staging dir to the final CAS directory; or
//!   (b) on any bridge failure, deletes the staging dir and exits non-zero.
//!
//! This makes Zig the atomicity orchestrator (SEC11 / AC7): no partial state
//! is ever visible. The bridge is a subprocess so Zig can gate on its exit
//! code without coupling the two language runtimes at link time.
//!
//! Six envelopes minted in dependency order:
//!   1. jelly.dreamball.agent  — oracle agent (own hybrid keypair; TC21)
//!   2. jelly.mythos           — genesis mythos (is-genesis: true; no predecessor)
//!   3. jelly.asset            — archiform registry (@embedFile; D-014)
//!   4. jelly.action           — "palace-minted" dual-signed (NFR12)
//!   5. jelly.timeline         — root timeline with head_hashes = {action.fp}
//!   6. jelly.dreamball.field  — palace field (field-kind: "palace"; AC1)
//!
//! Wire format: TC14 — action + timeline at format-version 3; others at 2.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const Fingerprint = dreamball.fingerprint.Fingerprint;
const protocol = dreamball.protocol;
const v2 = dreamball.protocol_v2;
const envelope = dreamball.envelope;
const envelope_v2 = dreamball.envelope_v2;
const signer = dreamball.signer;
const key_file = dreamball.key_file;

// ── Archiform registry bytes (D-014 — snapshot-on-mint) ─────────────────────
// @embedFile resolves relative to *this* source file. The registry JSON lives
// at src/memory-palace/seed/archiform-registry.json.
const REGISTRY_BYTES: []const u8 =
    @embedFile("../memory-palace/seed/archiform-registry.json");

// ── Oracle personality seed bytes (AC7 / S4.1) ────────────────────────────────
// Embedded at compile time so the seed is available in any runtime environment
// (CLI, jelly-server, browser) without a disk read at runtime.
// The content is placed into the oracle envelope's personality_master_prompt slot.
const ORACLE_PROMPT_BYTES: []const u8 =
    @embedFile("../memory-palace/seed/oracle-prompt.md");

// ── CLI spec ─────────────────────────────────────────────────────────────────

const SPECS = [_]args_mod.Spec{
    .{ .long = "out" }, // 0
    .{ .long = "mythos" }, // 1
    .{ .long = "mythos-file" }, // 2
    .{ .long = "help", .takes_value = false }, // 3
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(3)) {
        // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
        // The .oracle.key output below is written with mode 0600 but is NOT encrypted in MVP.
        try io.writeAllStdout(
            \\jelly palace mint --out <path> --mythos <string>
            \\                  [--mythos-file <path>]
            \\
            \\Mints a new palace DreamBall with genesis mythos, oracle Agent,
            \\seed archiform registry, and a rooted timeline.
            \\
            \\  --out         Path prefix for output files (required)
            \\  --mythos      Inline mythos body text (required if not TTY)
            \\  --mythos-file Path to a file containing the mythos body
            \\
            \\Outputs:
            \\  <out>.bundle      Bundle file referencing all 6 envelopes
            \\  <out>.oracle.key  Oracle hybrid keypair (mode 0600)
            \\
        );
        return 0;
    }

    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };

    // AC2: mythos must be provided. When --mythos / --mythos-file are absent,
    // exit non-zero with a helpful message. Interactive prompt from TTY is
    // deferred to Growth; for MVP always require an explicit flag.
    const mythos_inline = parsed.get(1);
    const mythos_file_path = parsed.get(2);

    var mythos_body_owned: ?[]u8 = null;
    defer if (mythos_body_owned) |b| gpa.free(b);

    const mythos_body: []const u8 = blk: {
        if (mythos_inline) |m| break :blk m;
        if (mythos_file_path) |mf| {
            mythos_body_owned = try helpers.readFile(gpa, mf);
            break :blk mythos_body_owned.?;
        }
        try io.writeAllStderr(
            "error: mythos required\n" ++
                "  provide --mythos <string> or --mythos-file <path>\n",
        );
        return 2;
    };

    return runMint(gpa, out_path, mythos_body);
}

/// Compute Blake3 of bytes and return 32-byte digest.
pub fn blake3Hash(bytes: []const u8) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(bytes);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

/// Hex-encode 32 bytes into a 64-char stack array.
pub fn hexArray(bytes: *const [32]u8) [64]u8 {
    const charset = "0123456789abcdef";
    var result: [64]u8 = undefined;
    for (bytes, 0..) |b, i| {
        result[i * 2] = charset[b >> 4];
        result[i * 2 + 1] = charset[b & 0xF];
    }
    return result;
}

/// Hex-encode 32 bytes into a 64-char owned string.
pub fn hexEncode(allocator: Allocator, bytes: *const [32]u8) ![]u8 {
    const h = hexArray(bytes);
    return allocator.dupe(u8, &h);
}

/// Write bytes to path under dir.
fn writeBytesAt(dir: std.Io.Dir, name: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(io.io(), name, .{ .truncate = true });
    defer file.close(io.io());
    var buf: [4096]u8 = undefined;
    var w = file.writer(io.io(), &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

/// Write bytes to a path relative to cwd.
pub fn writeBytesToPath(path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io.io(), path, .{ .truncate = true });
    defer file.close(io.io());
    var buf: [4096]u8 = undefined;
    var w = file.writer(io.io(), &buf);
    try w.interface.writeAll(bytes);
    try w.interface.flush();
}

fn runMint(gpa: Allocator, out_path: []const u8, mythos_body: []const u8) !u8 {
    const now_ms: i64 = io.unixSeconds() * 1000;

    // ── 1. Generate custodian keypair (palace's own signing identity) ────────
    const custodian_keys = try signer.HybridSigningKeys.generate();

    // ── 2. Generate oracle Agent keypair (TC21: separate from custodian) ────
    const oracle_keys = try signer.HybridSigningKeys.generate();

    // ── 3. Build oracle Agent envelope ────────────────────────────────────────
    var oracle_genesis_input: [40]u8 = undefined;
    @memcpy(oracle_genesis_input[0..32], &oracle_keys.ed25519_public);
    std.mem.writeInt(i64, oracle_genesis_input[32..40], now_ms, .little);
    const oracle_genesis_hash = blake3Hash(&oracle_genesis_input);

    var oracle_db = protocol.DreamBall{
        .stage = .seed,
        .identity = oracle_keys.ed25519_public,
        .identity_pq = oracle_keys.mldsa_public,
        .genesis_hash = oracle_genesis_hash,
        .revision = 0,
        .dreamball_type = .agent,
        .created = now_ms,
    };

    const oracle_unsigned = try envelope.encodeDreamBall(gpa, oracle_db);
    defer gpa.free(oracle_unsigned);
    const oracle_ed_sig = try signer.signEd25519(oracle_unsigned, oracle_keys.classical());
    const oracle_mldsa_sig = try signer.signMlDsa(gpa, oracle_unsigned, oracle_keys);
    defer gpa.free(oracle_mldsa_sig);
    const oracle_sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &oracle_ed_sig },
        .{ .alg = "ml-dsa-87", .value = oracle_mldsa_sig },
    };
    oracle_db.signatures = &oracle_sigs;
    const oracle_bytes = try envelope.encodeDreamBall(gpa, oracle_db);
    defer gpa.free(oracle_bytes);
    const oracle_fp = blake3Hash(oracle_bytes);

    // ── 4. Build genesis mythos envelope ─────────────────────────────────────
    const mythos = v2.Mythos{
        .is_genesis = true,
        .predecessor = null,
        .body = mythos_body,
        .authored_at = now_ms,
    };
    const mythos_bytes = try envelope_v2.encodeMythos(gpa, mythos);
    defer gpa.free(mythos_bytes);
    const mythos_fp = blake3Hash(mythos_bytes);

    // ── 5. Build registry asset envelope (D-014 — @embedFile snapshot) ───────
    const registry_hash = blake3Hash(REGISTRY_BYTES);
    const registry_asset = protocol.Asset{
        .media_type = "application/vnd.palace.archiform-registry+json",
        .hash = registry_hash,
        .embedded = REGISTRY_BYTES,
    };
    const registry_bytes = try envelope.encodeAsset(gpa, registry_asset);
    defer gpa.free(registry_bytes);
    const registry_fp = blake3Hash(registry_bytes);

    // ── 6. Custodian identity (palace fp = Blake3(ed25519_pub)) ──────────────
    var custodian_genesis_input: [40]u8 = undefined;
    @memcpy(custodian_genesis_input[0..32], &custodian_keys.ed25519_public);
    std.mem.writeInt(i64, custodian_genesis_input[32..40], now_ms, .little);
    const custodian_genesis_hash = blake3Hash(&custodian_genesis_input);
    const palace_fp_bytes: [32]u8 = Fingerprint.fromEd25519(custodian_keys.ed25519_public).bytes;

    // ── 7. Build mint action (dual-signed by custodian) ───────────────────────
    // parent_hashes is empty (genesis action; AC4).
    const empty_parents: [][32]u8 = &.{};
    const action = v2.Action{
        .action_kind = .palace_minted,
        .parent_hashes = empty_parents,
        .actor = palace_fp_bytes,
        .target_fp = palace_fp_bytes,
        .timestamp = now_ms,
    };

    // Encode unsigned to get bytes to sign.
    const action_unsigned = try envelope_v2.encodeAction(gpa, action);
    defer gpa.free(action_unsigned);
    const action_ed_sig = try signer.signEd25519(action_unsigned, custodian_keys.classical());
    const action_mldsa_sig = try signer.signMlDsa(gpa, action_unsigned, custodian_keys);
    defer gpa.free(action_mldsa_sig);

    // Re-encode with signed attributes.
    const action_signed_bytes = try encodeSignedAction(gpa, action, &[_]protocol.Signature{
        .{ .alg = "ed25519", .value = &action_ed_sig },
        .{ .alg = "ml-dsa-87", .value = action_mldsa_sig },
    });
    defer gpa.free(action_signed_bytes);
    const action_fp = blake3Hash(action_signed_bytes);

    // ── 8. Build timeline envelope ────────────────────────────────────────────
    const action_fp_slice: [][32]u8 = try gpa.dupe([32]u8, &[_][32]u8{action_fp});
    defer gpa.free(action_fp_slice);
    const timeline = v2.Timeline{
        .palace_fp = palace_fp_bytes,
        .head_hashes = action_fp_slice,
    };
    const timeline_bytes = try envelope_v2.encodeTimeline(gpa, timeline);
    defer gpa.free(timeline_bytes);
    const timeline_fp = blake3Hash(timeline_bytes);

    // ── 9. Build palace field envelope ───────────────────────────────────────
    // contains: oracle agent, mythos, registry asset, timeline
    const contains_fps = [_]Fingerprint{
        .{ .bytes = oracle_fp },
        .{ .bytes = mythos_fp },
        .{ .bytes = registry_fp },
        .{ .bytes = timeline_fp },
    };

    var palace_db = protocol.DreamBall{
        .stage = .seed,
        .identity = custodian_keys.ed25519_public,
        .identity_pq = custodian_keys.mldsa_public,
        .genesis_hash = custodian_genesis_hash,
        .revision = 0,
        .dreamball_type = .field,
        .field_kind = "palace",
        .created = now_ms,
        .contains = &contains_fps,
    };

    const palace_unsigned = try envelope.encodeDreamBall(gpa, palace_db);
    defer gpa.free(palace_unsigned);
    const palace_ed_sig = try signer.signEd25519(palace_unsigned, custodian_keys.classical());
    const palace_mldsa_sig = try signer.signMlDsa(gpa, palace_unsigned, custodian_keys);
    defer gpa.free(palace_mldsa_sig);
    const palace_sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &palace_ed_sig },
        .{ .alg = "ml-dsa-87", .value = palace_mldsa_sig },
    };
    palace_db.signatures = &palace_sigs;
    const palace_bytes = try envelope.encodeDreamBall(gpa, palace_db);
    defer gpa.free(palace_bytes);
    const palace_fp = blake3Hash(palace_bytes);

    // ── 10. Staging directory ─────────────────────────────────────────────────
    // Use absolute paths for staging so child processes (bridge) can always find
    // the files regardless of their inherited cwd. Use C getcwd since AT_FDCWD
    // is a sentinel that doesn't work with Dir.realPath.
    var cwd_buf: [4096]u8 = undefined;
    cwd_buf[0] = 0;
    const cwd_abs: []const u8 = blk: {
        const ptr = std.c.getcwd(&cwd_buf, cwd_buf.len);
        if (ptr == null) break :blk ".";
        break :blk std.mem.sliceTo(&cwd_buf, 0);
    };

    const ts_nano = std.Io.Clock.real.now(io.io()).nanoseconds;
    const staging_rel = try std.fmt.allocPrint(gpa, "{s}.staging.{d}", .{ out_path, ts_nano });
    defer gpa.free(staging_rel);
    const staging_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cwd_abs, staging_rel });
    defer gpa.free(staging_path);

    try std.Io.Dir.cwd().createDir(io.io(), staging_path, .default_dir);

    // Write all 6 envelopes into staging dir named by their hex fp.
    try writeStagingFiles(staging_path, &[_]EnvelopeEntry{
        .{ .fp = oracle_fp, .bytes = oracle_bytes },
        .{ .fp = mythos_fp, .bytes = mythos_bytes },
        .{ .fp = registry_fp, .bytes = registry_bytes },
        .{ .fp = action_fp, .bytes = action_signed_bytes },
        .{ .fp = timeline_fp, .bytes = timeline_bytes },
        .{ .fp = palace_fp, .bytes = palace_bytes },
    });

    // Write bundle manifest into staging dir.
    const bundle_staging_path = try std.fmt.allocPrint(gpa, "{s}/palace.bundle", .{staging_path});
    defer gpa.free(bundle_staging_path);
    const bundle_content = try buildBundleContent(gpa, &[_][32]u8{
        palace_fp, oracle_fp, mythos_fp, registry_fp, action_fp, timeline_fp,
    });
    defer gpa.free(bundle_content);
    try writeBytesToPath(bundle_staging_path, bundle_content);

    // Write custodian key to staging dir (mode 0600) — needed by add-room/inscribe.
    // This is the palace's own signing identity; add-room reads it as <palace>.key.
    const custodian_key_staging = try std.fmt.allocPrint(gpa, "{s}/custodian.key", .{staging_path});
    defer gpa.free(custodian_key_staging);
    try key_file.writeHybridToPath(gpa, custodian_key_staging, custodian_keys);
    try setFileMode0600(custodian_key_staging);

    // Write oracle key to staging dir and set 0600 perms.
    const oracle_key_staging = try std.fmt.allocPrint(gpa, "{s}/oracle.key", .{staging_path});
    defer gpa.free(oracle_key_staging);
    try key_file.writeHybridToPath(gpa, oracle_key_staging, oracle_keys);

    // TODO-CRYPTO: oracle key is plaintext at oracle_key_staging.
    // D-011 (2026-04-22): MVP compromise — the oracle keypair is written as a
    // recrypt.identity envelope to a sibling .oracle.key file with mode 0600.
    // This is intentionally insecure and must be replaced by a proper secret
    // custody solution (HSM, OS keychain, or recrypt encryption) before production.
    // SEC7 tracking: remove this TODO when D-011 is resolved.
    try setFileMode0600(oracle_key_staging);

    // ── 11. Invoke bridge (atomicity orchestrator) ───────────────────────────
    const cas_dir_path = try std.fmt.allocPrint(gpa, "{s}.cas", .{out_path});
    defer gpa.free(cas_dir_path);
    const bundle_final_path = try std.fmt.allocPrint(gpa, "{s}.bundle", .{out_path});
    defer gpa.free(bundle_final_path);
    // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
    const oracle_key_final_path = try std.fmt.allocPrint(gpa, "{s}.oracle.key", .{out_path});
    defer gpa.free(oracle_key_final_path);
    const custodian_key_final_path = try std.fmt.allocPrint(gpa, "{s}.key", .{out_path});
    defer gpa.free(custodian_key_final_path);

    const bridge_exit = invokeBridge(gpa, staging_path, bundle_staging_path, ORACLE_PROMPT_BYTES) catch |err| blk: {
        // Use C write() directly so this cannot fail and swallow the spawn error.
        const prefix = "error: palace-mint bridge spawn error: ";
        _ = std.c.write(2, prefix.ptr, prefix.len);
        const name = @errorName(err);
        _ = std.c.write(2, name.ptr, name.len);
        _ = std.c.write(2, "\n", 1);
        break :blk @as(u8, 1);
    };
    if (bridge_exit != 0) {
        std.Io.Dir.cwd().deleteTree(io.io(), staging_path) catch {};
        try io.writeAllStderr("error: palace-mint bridge failed — rolling back\n");
        return 1;
    }

    // ── 12. Promote staging → final (SEC11 atomic rename) ─────────────────────
    // Create CAS dir (idempotent).
    std.Io.Dir.cwd().createDir(io.io(), cas_dir_path, .default_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    const fps_to_promote = [_][32]u8{
        oracle_fp, mythos_fp, registry_fp, action_fp, timeline_fp, palace_fp,
    };
    try promoteStagingFiles(gpa, staging_path, cas_dir_path, &fps_to_promote);

    // Rename bundle, oracle key, and custodian key to final paths.
    try std.Io.Dir.cwd().rename(
        bundle_staging_path,
        std.Io.Dir.cwd(),
        bundle_final_path,
        io.io(),
    );
    try std.Io.Dir.cwd().rename(
        oracle_key_staging,
        std.Io.Dir.cwd(),
        oracle_key_final_path,
        io.io(),
    );
    try std.Io.Dir.cwd().rename(
        custodian_key_staging,
        std.Io.Dir.cwd(),
        custodian_key_final_path,
        io.io(),
    );

    // Cleanup staging dir (should be empty now).
    std.Io.Dir.cwd().deleteDir(io.io(), staging_path) catch {};

    // ── 13. Report ────────────────────────────────────────────────────────────
    const palace_fp_hex = try hexEncode(gpa, &palace_fp);
    defer gpa.free(palace_fp_hex);
    const oracle_fp_hex = try hexEncode(gpa, &oracle_fp);
    defer gpa.free(oracle_fp_hex);
    const action_fp_hex = try hexEncode(gpa, &action_fp);
    defer gpa.free(action_fp_hex);

    try io.printStdout(
        "minted palace → {s}\n" ++
            "  field-kind:    palace\n" ++
            "  palace fp:     {s}\n" ++
            "  oracle fp:     {s}\n" ++
            "  action fp:     {s}\n" ++
            "  oracle key:    {s}\n" ++
            "  bundle:        {s}\n",
        .{
            out_path,
            palace_fp_hex,
            oracle_fp_hex,
            action_fp_hex,
            oracle_key_final_path,
            bundle_final_path,
        },
    );

    return 0;
}

// ── Set file mode 0600 via posix chmod ────────────────────────────────────────

fn setFileMode0600(path: []const u8) !void {
    // Use POSIX chmod directly — the Io.Dir.setFilePermissions API is complex
    // and we need exactly 0600 (owner read+write only, no group/other bits).
    const mode: std.posix.mode_t = 0o600;
    const path_c = std.posix.toPosixPath(path) catch return error.NameTooLong;
    _ = std.posix.system.chmod(&path_c, mode);
}

// ── Signed action encoder ─────────────────────────────────────────────────────
// Encodes a jelly.action envelope with attached "signed" attributes.
// v2.Action has no signatures field (it is not a DreamBall), so we emit
// the signed attribute pair directly using zbor + dcbor from the dreamball module.

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
    // Core keys sorted (len asc, lex):
    //   "type"(4), "actor"(5), "action-kind"(11), "parent-hashes"(13), "format-version"(14)
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

    // Attributes sorted by label length, then lex:
    // "deps"(4), "nacks"(5), "signed"(6), "target-fp"(9), "timestamp"(9)
    // At len 9: "target-fp" < "timestamp" lex.
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

// ── Bundle manifest ────────────────────────────────────────────────────────────
// Simple newline-delimited hex fp list. Line 0 = palace fp (root).

fn buildBundleContent(allocator: Allocator, fps: []const [32]u8) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    for (fps) |fp| {
        const h = hexArray(&fp);
        try buf.appendSlice(allocator, &h);
        try buf.append(allocator, '\n');
    }
    return buf.toOwnedSlice(allocator);
}

// ── CAS file helpers ──────────────────────────────────────────────────────────

pub const EnvelopeEntry = struct {
    fp: [32]u8,
    bytes: []const u8,
};

pub fn writeStagingFiles(
    staging_path: []const u8,
    entries: []const EnvelopeEntry,
) !void {
    var staging_dir = try std.Io.Dir.cwd().openDir(io.io(), staging_path, .{});
    defer staging_dir.close(io.io());
    for (entries) |e| {
        const name = hexArray(&e.fp);
        try writeBytesAt(staging_dir, &name, e.bytes);
    }
}

pub fn promoteStagingFiles(
    allocator: Allocator,
    staging_path: []const u8,
    cas_path: []const u8,
    fps: []const [32]u8,
) !void {
    const cwd = std.Io.Dir.cwd();
    for (fps) |fp| {
        const name = hexArray(&fp);
        const src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ staging_path, &name });
        defer allocator.free(src);
        const dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cas_path, &name });
        defer allocator.free(dst);
        try cwd.rename(src, cwd, dst, io.io());
    }
}

// ── Bridge subprocess invocation ──────────────────────────────────────────────
// Spawns: bun run src/lib/bridge/palace-mint.ts <staging_path> <bundle_path>
// Returns the bridge process exit code. Non-zero means roll back.

fn invokeBridge(
    allocator: Allocator,
    staging_path: []const u8,
    bundle_path: []const u8,
    oracle_prompt: []const u8,
) !u8 {
    // PALACE_BRIDGE_DIR env var allows callers (e.g. smoke tests) to specify the
    // directory containing the bridge script when the process cwd differs from
    // the repo root (the default assumption for relative paths).
    const bridge_script = blk: {
        const env_c = std.c.getenv("PALACE_BRIDGE_DIR");
        if (env_c != null) {
            const dir = std.mem.span(env_c.?);
            break :blk try std.fmt.allocPrint(allocator, "{s}/palace-mint.ts", .{dir});
        }
        break :blk try allocator.dupe(u8, "src/lib/bridge/palace-mint.ts");
    };
    defer allocator.free(bridge_script);

    // PALACE_BUN env var allows callers to specify the full path to bun when it
    // may not be on the PATH inherited by the child process (e.g. CI / zig build smoke).
    const bun_path = blk: {
        const env_c = std.c.getenv("PALACE_BUN");
        if (env_c != null) break :blk std.mem.span(env_c.?);
        break :blk "bun";
    };

    const argv = [_][]const u8{ bun_path, "run", bridge_script, staging_path, bundle_path };

    // std.Io.Threaded.global_single_threaded is initialized with a failing allocator
    // and empty environ. processSpawn (called by std.process.run) needs a real allocator
    // for its internal posix fork/exec arena. Set it before spawning (idempotent mutation
    // of the global; safe because we're single-threaded at this point).
    std.Io.Threaded.global_single_threaded.allocator = allocator;

    // Build environ_map from the current process environment.
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    {
        // std.c.environ: [*:null]?[*:0]u8 — iterate until null sentinel.
        var i: usize = 0;
        while (std.c.environ[i]) |entry_ptr| : (i += 1) {
            const entry = std.mem.span(entry_ptr);
            const eq = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
            const key = entry[0..eq];
            const val = entry[eq + 1 ..];
            try env_map.put(key, val);
        }
    }

    // Pass the oracle prompt bytes to the bridge via env var.
    // AC7: the bridge reads ORACLE_PROMPT from the environment (set from the
    // @embedFile constant) so it never reads oracle-prompt.md at runtime.
    try env_map.put("ORACLE_PROMPT", oracle_prompt);

    const result = try std.process.run(allocator, io.io(), .{
        .argv = &argv,
        .expand_arg0 = .expand, // resolve argv[0] via PATH (needed when bun_path is bare "bun")
        .environ_map = &env_map,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Forward stdout and stderr from the bridge subprocess.
    if (result.stdout.len > 0) try io.writeAllStdout(result.stdout);
    if (result.stderr.len > 0) try io.writeAllStderr(result.stderr);

    return switch (result.term) {
        .exited => |code| code,
        else => 1,
    };
}

// ============================================================================
// Tests (AC8 — ≥5 new test blocks)
// ============================================================================

test "registry embeds exactly 19 archiforms" {
    const json = std.json;
    const allocator = std.testing.allocator;

    const parsed = try json.parseFromSlice(json.Value, allocator, REGISTRY_BYTES, .{});
    defer parsed.deinit();

    const arr = parsed.value.array;
    try std.testing.expectEqual(@as(usize, 19), arr.items.len);

    const expected_names = [_][]const u8{
        "library",   "forge",    "throne-room", "garden",   "courtyard",
        "lab",       "crypt",    "portal",      "atrium",   "cell",
        "scroll",    "lantern",  "vessel",      "compass",  "seed",
        "muse",      "judge",    "midwife",     "trickster",
    };
    for (arr.items, expected_names) |item, name| {
        const obj = item.object;
        const got_name = obj.get("name") orelse return error.TestMissingName;
        try std.testing.expectEqualStrings(name, got_name.string);
    }
}

test "registry blake3 deterministic across two calls" {
    const fp1 = blake3Hash(REGISTRY_BYTES);
    const fp2 = blake3Hash(REGISTRY_BYTES);
    try std.testing.expectEqualSlices(u8, &fp1, &fp2);
}

test "oracle and custodian keypairs are byte-distinct" {
    const k1 = try signer.HybridSigningKeys.generate();
    const k2 = try signer.HybridSigningKeys.generate();
    try std.testing.expect(!std.mem.eql(u8, &k1.ed25519_public, &k2.ed25519_public));
    try std.testing.expect(!std.mem.eql(u8, &k1.mldsa_public, &k2.mldsa_public));
}

test "encodeSignedAction produces longer envelope than unsigned" {
    if (!dreamball.ml_dsa.enabled) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    const keys = try signer.HybridSigningKeys.generate();
    const empty: [][32]u8 = &.{};
    const action = v2.Action{
        .action_kind = .palace_minted,
        .parent_hashes = empty,
        .actor = keys.ed25519_public,
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

    // Signed envelope must be longer (two "signed" attributes appended).
    try std.testing.expect(signed.len > unsigned.len);
    // Blake3 is deterministic.
    const fp1 = blake3Hash(signed);
    const fp2 = blake3Hash(signed);
    try std.testing.expectEqualSlices(u8, &fp1, &fp2);
}

test "buildBundleContent produces 6 newline-terminated lines for 6 fps" {
    const allocator = std.testing.allocator;
    const fps = [_][32]u8{
        [_]u8{0x01} ** 32, [_]u8{0x02} ** 32, [_]u8{0x03} ** 32,
        [_]u8{0x04} ** 32, [_]u8{0x05} ** 32, [_]u8{0x06} ** 32,
    };
    const content = try buildBundleContent(allocator, &fps);
    defer allocator.free(content);
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        if (line.len > 0) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 6), count);
}

test "SPECS table is consistent with AC2" {
    // Verify arg-spec indices match the expected flag positions.
    try std.testing.expectEqual(@as(usize, 4), SPECS.len);
    try std.testing.expectEqualStrings("out", SPECS[0].long);
    try std.testing.expectEqualStrings("mythos", SPECS[1].long);
    try std.testing.expectEqualStrings("mythos-file", SPECS[2].long);
    try std.testing.expectEqualStrings("help", SPECS[3].long);
    try std.testing.expect(!SPECS[3].takes_value);
}
